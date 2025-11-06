# M2-Informatique-R-seau-Conteneurisation-Orchestration

0) Pré-requis
# Namespace
kubectl create ns observability || true


Hosts (Windows) — ouvrir C:\Windows\System32\drivers\etc\hosts en Administrateur et ajouter sur 1 ligne :

127.0.0.1 grafana.local prometheus.local alertmanager.local jaeger.local

1) Installation des stacks
# Prometheus + Grafana
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitor prometheus-community/kube-prometheus-stack -n observability --create-namespace
```
# Loki + Promtail (logs)
```
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack -n observability --set promtail.enabled=true
```
2) Ingress + TLS (interfaces Web)
```
s7/k8s/ing-observability.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: observability
  namespace: observability
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: selfsigned
spec:
  tls:
  - hosts: [grafana.local, prometheus.local, alertmanager.local, jaeger.local]
    secretName: obs-tls
  rules:
  - host: grafana.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: monitor-grafana, port: { number: 80 } } }
  - host: prometheus.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: monitor-kube-prometheus-st-prometheus, port: { number: 9090 } } }
  - host: alertmanager.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: monitor-kube-prometheus-st-alertmanager, port: { number: 9093 } } }
  - host: jaeger.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: simplest-query, port: { number: 16686 } } }

kubectl apply -f s7/k8s/ing-observability.yaml
```

Accès :
```
https://grafana.local

https://prometheus.local

https://alertmanager.local

https://jaeger.local
```
(Sur le premier accès, accepter le certificat autosigné.)

3) Datasource Grafana → Prometheus

Dans Grafana (https://grafana.local) :
Connections > Data sources > Add data source > Prometheus
```
URL : http://monitor-kube-prometheus-st-prometheus.observability.svc.cluster.local:9090
(ou simplement http://monitor-kube-prometheus-st-prometheus:9090)
```
Auth : No Auth

Save & test → Successfully queried the Prometheus API.

4) Scrape NGINX Ingress (metrics ingress-nginx)

Créer un ServiceMonitor pour le contrôleur NGINX (si pas déjà présent via chart) et ajouter le label attendu par Prometheus (release monitor) :
```
kubectl -n observability label servicemonitor ingress-nginx release=monitor --overwrite

```
Vérifier la cible côté Prometheus :

# (optionnel) forward, puis ouvrir http://127.0.0.1:9090/targets
```
kubectl -n observability port-forward svc/monitor-kube-prometheus-st-prometheus 9090:9090
```
5) Traces Jaeger (optionnel mais conseillé)
```
s7/k8s/hotrod.yaml

apiVersion: apps/v1
kind: Deployment
metadata: { name: hotrod, namespace: observability, labels: { app: hotrod } }
spec:
  replicas: 1
  selector: { matchLabels: { app: hotrod } }
  template:
    metadata: { labels: { app: hotrod } }
    spec:
      containers:
      - name: hotrod
        image: jaegertracing/example-hotrod:1.57
        ports: [{ name: http, containerPort: 8080 }]
        env:
        - name: JAEGER_ENDPOINT
          value: http://simplest-collector.observability.svc:14268/api/traces
        - name: JAEGER_DISABLED
          value: "false"
---
apiVersion: v1
kind: Service
metadata: { name: hotrod, namespace: observability }
spec:
  selector: { app: hotrod }
  ports: [{ name: http, port: 8080, targetPort: http }]

kubectl apply -f s7/k8s/hotrod.yaml
kubectl -n observability port-forward svc/hotrod 8080:8080 >/dev/null 2>&1 &
# Générer quelques traces
for i in {1..20}; do curl -s "http://127.0.0.1:8080/dispatch?customer=42&nonce=$i" >/dev/null; done
```

Ouvrir https://jaeger.local → onglet Search, service hotrod.

6) Dashboard Grafana — Latence / Erreurs / Saturation

Créer un nouveau dashboard avec 3 panels (datasource = Prometheus) :
```
Panel 1 — Latence p95 Ingress
histogram_quantile(
  0.95,
  sum by (le) (
    rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])
  )
)
```

Viz : Time series

Unité : seconds

Légende : p95 ingress latency

Panel 2 — Taux d’erreurs 5xx Ingress (%)
```
100 *
sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
/
sum(rate(nginx_ingress_controller_requests[5m]))
```

Viz : Stat ou Time series

Unité : percent (0-100)

Seuils : warn ≥ 1, critical ≥ 2

Panel 3 — Saturation CPU par namespace
```
sum by (namespace) (
  rate(container_cpu_usage_seconds_total{image!=""}[5m])
)

```
Viz : Bar chart ou Time series

Unité : cores (ou % si tu normalises)

(Exemple Prometheus déjà validé dans ta capture : somme CPU par namespace.)

7) Deux alertes Prometheus (PrometheusRule)
```
s7/k8s/alerts.yaml

apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: workshop-alerts
  namespace: observability
  labels:
    release: monitor
spec:
  groups:
  - name: api.rules
    rules:
    # Alerte 1 — Erreurs 5xx > 2% pendant 10 min
    - alert: HighErrorRateIngress
      expr: |
        ( sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
          /
          sum(rate(nginx_ingress_controller_requests[5m])) ) > 0.02
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Taux d'erreurs 5xx > 2% sur Ingress"
        description: "Sur 10 minutes, la proportion de 5xx dépasse 2%."
        runbook_url: "s7/docs/runbook-HighErrorRateIngress.md"

    # Alerte 2 — Redémarrages anormaux de pods sur 15 min
    - alert: PodHighRestarts
      expr: increase(kube_pod_container_status_restarts_total[15m]) > 5
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "Redémarrages anormaux de pods"
        description: "Plus de 5 redémarrages cumulés sur 15 minutes."
        runbook_url: "s7/docs/runbook-PodHighRestarts.md"

kubectl apply -f s7/k8s/alerts.yaml
```


# Runbook — HighErrorRateIngress

Déclencheur : (5xx / toutes req) > 2% pendant 10 min (Ingress NGINX).

Vérifications rapides :
1) Grafana → Dashboard Latence/Erreurs : confirmer le pic d’erreurs.
2) Prometheus → requête par code & backend :
   sum by (status, service) (rate(nginx_ingress_controller_requests[5m]))
3) NGINX & app pods :
   kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=200
   kubectl -n <ns-app> get po -owide
4) Santé backends (readiness/liveness) :
   kubectl -n <ns-app> describe po <pod>

Actions :
- Si un service est fautif (5xx applicatifs), rollback déploiement (Argo/GitOps).
- Si saturation, scaler (HPA) ou augmenter ressources.
- Si problème réseau/DNS, vérifier endpoints, Services, Probes.


s7/docs/runbook-PodHighRestarts.md

# Runbook — PodHighRestarts

Déclencheur : increase(kube_pod_container_status_restarts_total[15m]) > 5

Vérifications rapides :
1) kubectl -n <ns> get po | grep -v Running
2) kubectl -n <ns> describe po <pod>
3) Logs :
   kubectl -n <ns> logs <pod> --previous --tail=200
4) Ressources/Probes :
   vérifier readiness/liveness, CPU/memory (OOMKilled ?)

Actions :
- Corriger crashloop (config, secrets, endpoints).
- Ajuster ressources ou probes si trop strictes.
- Si image récente → rollback.


Contrôle : https://alertmanager.local (les alertes apparaîtront quand les conditions sont vraies).

8) Preuves 
<img width="2228" height="422" alt="Capture d&#39;écran 2025-11-06 095640" src="https://github.com/user-attachments/assets/c7cec9c0-68a3-40d4-a6a4-31b19a9ce489" />
<img width="2548" height="1235" alt="Capture d&#39;écran 2025-11-06 095720" src="https://github.com/user-attachments/assets/610d0f8f-22c2-45e3-b52d-6c8ef090703b" />
<img width="2534" height="847" alt="Capture d&#39;écran 2025-11-06 095728" src="https://github.com/user-attachments/assets/4141b193-85a8-4949-9bcb-73ac2d185407" />
<img width="2553" height="873" alt="Capture d&#39;écran 2025-11-06 095831" src="https://github.com/user-attachments/assets/372c5542-db18-4a06-aaf2-0e43aaeaa181" />
<img width="2555" height="170" alt="Capture d&#39;écran 2025-11-06 095846" src="https://github.com/user-attachments/assets/39b7a199-785a-469e-adf6-8cd3ba6467af" />
<img width="2554" height="228" alt="Capture d&#39;écran 2025-11-06 095900" src="https://github.com/user-attachments/assets/d9b7eb6e-cb3b-4524-b75f-7bba22340ebc" />
<img width="2505" height="320" alt="Capture d&#39;écran 2025-11-06 095915" src="https://github.com/user-attachments/assets/f901a6a8-138e-4bbc-9de7-b2ab097a4077" />
<img width="2552" height="1141" alt="Capture d&#39;écran 2025-11-06 095927" src="https://github.com/user-attachments/assets/af808e65-5a65-47bc-a5f5-f2f4ebe2ccd8" />
<img width="2530" height="196" alt="Capture d&#39;écran 2025-11-06 095938" src="https://github.com/user-attachments/assets/da99bf97-66cc-4b41-88c6-344dd630adb6" />
<img width="2559" height="1256" alt="Capture d&#39;écran 2025-11-06 100356" src="https://github.com/user-attachments/assets/17dd7c9d-81ae-4a42-892f-e2d1bce7c5cd" />
<img width="1534" height="265" alt="Capture d&#39;écran 2025-11-06 100404" src="https://github.com/user-attachments/assets/d4891889-4fc8-4388-849a-d54f8b084115" />
<img width="1571" height="361" alt="Capture d&#39;écran 2025-11-06 100409" src="https://github.com/user-attachments/assets/61051efd-79b0-4383-a0c9-b5b65d2dc5b6" />
<img width="1548" height="421" alt="Capture d&#39;écran 2025-11-06 100417" src="https://github.com/user-attachments/assets/fad1dd32-f963-466a-930e-1120dbc55a8b" />
<img width="2555" height="1156" alt="Capture d&#39;écran 2025-11-06 100427" src="https://github.com/user-attachments/assets/2632a089-0afe-4e49-a9b9-dc48a367ff7c" />
<img width="2551" height="1047" alt="Capture d&#39;écran 2025-11-06 100434" src="https://github.com/user-attachments/assets/1f0ab5e1-33d7-4bfe-a8ab-0ddb820dee43" />
<img width="2545" height="1304" alt="Capture d&#39;écran 2025-11-06 100456" src="https://github.com/user-attachments/assets/91410469-fd79-48ce-af2e-beb19806905e" />
<img width="2557" height="1195" alt="Capture d&#39;écran 2025-11-06 100519" src="https://github.com/user-attachments/assets/8c487efb-4233-406a-8571-e8d0c92e5638" />
<img width="2559" height="1333" alt="Capture d&#39;écran 2025-11-06 100651" src="https://github.com/user-attachments/assets/c9e7b7f2-a4ec-4a73-abb1-345e2bf02330" />




9) Nettoyage (optionnel)
helm -n observability uninstall monitor || true
helm -n observability uninstall loki || true
kubectl delete -f s7/k8s/hotrod.yaml || true
kubectl delete -f s7/k8s/alerts.yaml || true
kubectl -n observability delete ingress observability || true

Annexe — Requêtes utiles Prometheus

Latence p95 Ingress :

histogram_quantile(0.95, sum by (le) (rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])))


Taux d’erreurs 5xx Ingress :

100 * sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
    / sum(rate(nginx_ingress_controller_requests[5m]))


CPU par namespace :

sum by (namespace) (rate(container_cpu_usage_seconds_total{image!=""}[5m]))


Redémarrages par pod (debug) :

increase(kube_pod_container_status_restarts_total[15m])
