# M2-Informatique-R-seau-Conteneurisation-Orchestration
Prérequis
```
Cluster Kind/WSL2 avec Ingress NGINX (S4).

kubectl, docker dispo côté WSL2.

workshop.local résolu sur WSL2 et Windows.
```
Manifests clés
Deployment (extrait) — s6/k8s/20-deploy-api.yaml
```
apiVersion: apps/v1
kind: Deployment
metadata: { name: api, namespace: workshop }
spec:
  replicas: 2
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
        - name: api
          image: kennethreitz/httpbin
          ports: [{ name: http, containerPort: 80 }]
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "300m", memory: "256Mi" }
          readinessProbe:
            httpGet: { path: /status/200, port: http }
            initialDelaySeconds: 5
            periodSeconds: 5
```
HPA — s6/k8s/30-hpa-api.yaml
```
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: api-hpa, namespace: workshop }
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```
PDB — s6/k8s/40-pdb-api.yaml
```
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: api-pdb, namespace: workshop }
spec:
  minAvailable: 2
  selector: { matchLabels: { app: api } }

(Bonus) Rollout canary — s6/k8s/50-rollout-api.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata: { name: api, namespace: workshop }
spec:
  replicas: 4
  selector: { matchLabels: { app: api } }
  strategy:
    canary:
      steps:
        - setWeight: 10
        - pause: { duration: 60 }
        - setWeight: 30
        - pause: { duration: 120 }
        - setWeight: 60
        - pause: { duration: 180 }
  template:
    metadata:
      labels: { app: api }
      annotations: { rollouts/version: "v1" }
    spec:
      containers:
        - name: api
          image: kennethreitz/httpbin:latest
          ports: [{ name: http, containerPort: 80 }]
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "300m", memory: "256Mi" }
```
Déploiement / Mise à jour
# Namespace
```
kubectl apply -f s6/k8s/20-deploy-api.yaml
kubectl apply -f s6/k8s/21-svc-api.yaml
kubectl apply -f s6/k8s/30-hpa-api.yaml
kubectl apply -f s6/k8s/40-pdb-api.yaml
# (bonus) Rollout : supprimer le Deployment api avant si besoin
# kubectl -n workshop delete deploy/api
# kubectl apply -f s6/k8s/50-rollout-api.yaml
```
Preuves demandées (commandes)
# HPA / charge
```
kubectl -n workshop describe hpa api-hpa > s6/docs/proofs/hpa-describe.txt
kubectl -n workshop top pods > s6/docs/proofs/top-pods.txt
kubectl -n workshop get deploy api -o jsonpath='{.status.replicas}{" / "}{.status.readyReplicas}{"\n"}' \
  > s6/docs/proofs/deploy-replicas.txt 2>/dev/null || true
```
# PDB : éviction refusée (à 2 pods)
```
kubectl get pdb api-pdb -n workshop -o yaml > s6/docs/proofs/pdb.yaml
POD=$(kubectl get po -n workshop -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl evict pod/$POD -n workshop --force --grace-period=0 || true
kubectl get events -n workshop --sort-by=.lastTimestamp | tail -n 40 \
  > s6/docs/proofs/pdb-eviction-events.txt
```
# (bonus) Rollout
```
kubectl -n workshop describe rollout api > s6/docs/proofs/rollout-describe.txt 2>/dev/null || true

Script k6 & exécution
s6/k6/load.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    rps: {
      executor: 'constant-arrival-rate',
      rate: 50, timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 20, maxVUs: 50
    }
  },
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed:   ['rate<0.01']
  }
};

export default () => {
  const res = http.get('https://workshop.local/api/status/200');
  check(res, { 'status 200': r => r.status === 200 });
};
```
Lancer le test et archiver les résultats
```
mkdir -p s6/k6
TS=$(date +%F-%H%M%S)
docker run --rm \
  --add-host workshop.local:host-gateway \
  -v "$(pwd)/s6/k6:/scripts:rw" -w /scripts \
  grafana/k6:latest run --insecure-skip-tls-verify load.js \
  | tee "s6/k6/results-$TS.txt"
```
Fiche SLO/SLI (remplie – exemple)

Remarque : Les valeurs ci-dessous sont exemple (issues d’une exécution typique).
Remplace si besoin par celles de s6/k6/results-*.txt et kubectl top.

SLI	SLO (cible)	Observé (exemple)	Source/mesure	Statut
Disponibilité HTTP	≥ 99.5 % / 30 j	99.9 %	1 - http_req_failed (k6)	✅
Latence p95	< 300 ms	180 ms	http_req_duration p(95) (k6)	✅
Taux d’erreur	< 1 %	0.1 %	http_req_failed rate (k6)	✅
Saturation CPU (pods API)	proche 60 %	~55–70 %	kubectl top pods (pendant la charge)	✅
Saturation Mémoire (pods API)	stable	~120–160 Mi	kubectl top pods (pendant la charge)	✅

Résultats k6 : s6/k6/results-*.txt

Captures HPA/Events : s6/docs/proofs/*.txt

Démo HPA (scale-up / scale-down)
# Démarrer un burn CPU dans tous les pods API
```
for p in $(kubectl -n workshop get po -l app=api -o name); do
  kubectl -n workshop exec $p -- sh -lc 'yes > /dev/null & echo $! >/tmp/burn.pid'
done
```
# Observer la montée (1–3 min)
```
watch -n1 'kubectl -n workshop describe hpa api-hpa | sed -n "1,120p"; echo; kubectl -n workshop top pods'
```
# Stopper le burn
```
for p in $(kubectl -n workshop get po -l app=api -o name); do
  kubectl -n workshop exec $p -- sh -lc 'kill -9 $(cat /tmp/burn.pid) 2>/dev/null || true'
done
```
PDB (preuve éviction refusée)

À 2 pods Ready, l’éviction d’un pod doit être refusée (minAvailable=2).
```
kubectl get pdb api-pdb -n workshop
POD=$(kubectl get po -n workshop -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl evict pod/$POD -n workshop --force --grace-period=0 || true
kubectl get events -n workshop --sort-by=.lastTimestamp | tail -n 40
```
(Bonus) Canary avec Argo Rollouts
# Installer le contrôleur
```
kubectl create ns argo-rollouts 2>/dev/null || true
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Appliquer le Rollout (si ce n'est pas déjà fait)
# kubectl -n workshop delete deploy/api
kubectl apply -f s6/k8s/50-rollout-api.yaml

# Déclencher une nouvelle release (canary) via annotation
kubectl -n workshop patch rollout api --type=merge -p \
'{"spec":{"template":{"metadata":{"annotations":{"rollouts/version":"v2"}}}}}'

# Suivi
kubectl -n workshop describe rollout api | sed -n '1,200p'
kubectl -n workshop get events --sort-by=.lastTimestamp | tail -n 40
```
Nettoyage / Reset
# Rétablir HPA min/max par défaut
```
kubectl -n workshop patch hpa api-hpa --type=merge -p '{"spec":{"minReplicas":2,"maxReplicas":6}}'
```
# Preuve 
<img width="2559" height="1246" alt="Capture d&#39;écran 2025-11-04 162542" src="https://github.com/user-attachments/assets/c5a1fb81-11d9-4865-9385-338a82151d6b" />
<img width="2502" height="172" alt="Capture d&#39;écran 2025-11-04 162556" src="https://github.com/user-attachments/assets/f390f316-35cc-477f-8476-544482859cef" />
<img width="1873" height="114" alt="Capture d&#39;écran 2025-11-04 162608" src="https://github.com/user-attachments/assets/ef3e007b-c905-4922-909f-94aefeb37f05" />
<img width="2154" height="60" alt="Capture d&#39;écran 2025-11-04 162621" src="https://github.com/user-attachments/assets/b24cd3ad-aadf-4f0f-a099-162ea11f63ba" />
<img width="2422" height="87" alt="Capture d&#39;écran 2025-11-04 162633" src="https://github.com/user-attachments/assets/42362bdf-6f8b-477a-a647-aab9eb011fb3" />

