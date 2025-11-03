# TP S4 — Ingress, TLS, Config & Secrets

## 1. Executive Summary
Déploiement d’un front statique et d’une API derrière un **Ingress NGINX** (L7) avec **TLS** géré par **cert-manager** (ClusterIssuer `selfsigned`).  
Objectifs opérationnels :
- Routage `/front` → service `front`, `/api/*` → service `api`
- Gestion de configuration : `ConfigMap` (non sensible) et `Secret` (credentials)
- Procédure de **rollback** documentée

## 2. Scope
- **Cluster** : Kind local (WSL2) — 1 control-plane
- **Ingress Controller** : ingress-nginx
- **PKI** : cert-manager + `ClusterIssuer/selfsigned`
- **Images** :
  - Front : `nginx:alpine` (recommandé pour “Welcome to nginx!”)  
    *(alternatif : `nginxdemos/hello:plain-text`)*
  - API : `kennethreitz/httpbin`

## 3. Arborescence
k8s/
00-namespace.yaml
10-configmap.yaml
11-secret.yaml
20-deploy-front.yaml
21-svc-front.yaml
30-deploy-api.yaml
31-svc-api.yaml
40-clusterissuer.yaml
50-ingress.yaml
README.md
diagram.md

markdown
Copier le code

## 4. Prérequis
- Docker Desktop (visible depuis WSL2)
- kubectl ≥ 1.27, helm ≥ 3.12, kind
- Résolution locale :
  - **WSL2** : `echo "127.0.0.1 workshop.local" | sudo tee -a /etc/hosts`
  - **Windows** : ajouter `127.0.0.1 workshop.local` dans `C:\Windows\System32\drivers\etc\hosts`
- Contrôleur Ingress + cert-manager installés (NodePort 30080/30443 exposés sur 80/443 côté host si Kind)

> Certificat **auto-signé** → avertissement navigateur **attendu**. Utiliser `curl -k` pour les tests.

## 5. Déploiement (idempotent)
```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/10-configmap.yaml
kubectl apply -f k8s/11-secret.yaml
kubectl apply -f k8s/20-deploy-front.yaml
kubectl apply -f k8s/21-svc-front.yaml
kubectl apply -f k8s/30-deploy-api.yaml
kubectl apply -f k8s/31-svc-api.yaml
kubectl apply -f k8s/40-clusterissuer.yaml
kubectl apply -f k8s/50-ingress.yaml
(Optionnel) Image front “Welcome to nginx!”
bash
Copier le code
kubectl -n workshop set image deploy/front front=nginx:alpine --record
kubectl -n workshop rollout status deploy/front
6. Vérifications (Acceptance)
6.1 Ingress + TLS
bash
Copier le code
kubectl -n workshop get deploy,po,svc,ingress
kubectl -n workshop describe ingress web | sed -n '1,140p'
kubectl -n workshop get certificate,certificaterequest,secret | grep web-tls || true
kubectl -n workshop get secret web-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -text | head -n 20

curl -ik https://workshop.local/front
curl -ik https://workshop.local/api/get
6.2 ConfigMap & Secret injectés
bash
Copier le code
kubectl -n workshop exec deploy/front -- printenv | grep BANNER_TEXT
kubectl -n workshop exec deploy/api -- printenv | egrep 'DB_USER|DB_PASS'
7. Runbook — Rollback
bash
Copier le code
# Dégradation volontaire
kubectl -n workshop set image deploy/front front=nginx:broken --record
kubectl -n workshop get pods -l app=front -o wide     # -> ImagePullBackOff attendu
kubectl -n workshop rollout history deploy/front

# Retour arrière
kubectl -n workshop rollout undo deploy/front
kubectl -n workshop rollout status deploy/front
Si un pod bloque la terminaison :

bash
Copier le code
kubectl -n workshop scale deploy/front --replicas=0
kubectl -n workshop wait --for=delete pod -l app=front --timeout=60s
kubectl -n workshop scale deploy/front --replicas=2
kubectl -n workshop rollout status deploy/front
8. Points d’attention / Troubleshooting
/front → 503 : pods non Ready / image non tirée.
Remède (Kind) : docker pull nginx:alpine && kind load docker-image nginx:alpine --name tp-s4

/api/get → 404 : vérifier réécriture Ingress :

yaml
Copier le code
annotations:
  nginx.ingress.kubernetes.io/use-regex: "true"
  nginx.ingress.kubernetes.io/rewrite-target: "/$2"
paths:
  - path: /front(/|$)(.*)
  - path: /api(/|$)(.*)
Cert non émis : kubectl -n workshop describe certificate web-tls

kubectl -n cert-manager logs deploy/cert-manager --tail=100

9. Nettoyage
bash
Copier le code
kubectl delete ns workshop
# cluster Kind dédié :
# kind delete cluster --name tp-s4
```

## 6. preuves :
<img width="2350" height="618" alt="Capture d&#39;écran 2025-11-03 162708" src="https://github.com/user-attachments/assets/150440ed-d51f-4bf6-b037-771a5810979e" />
<img width="2543" height="1297" alt="Capture d&#39;écran 2025-11-03 161955" src="https://github.com/user-attachments/assets/374512ee-add9-48bd-a226-60f65651973d" />
<img width="2559" height="1217" alt="Capture d&#39;écran 2025-11-03 162007" src="https://github.com/user-attachments/assets/0887143e-142f-4f43-b212-6831402f109c" />
<img width="2559" height="1260" alt="Capture d&#39;écran 2025-11-03 162014" src="https://github.com/user-attachments/assets/15dc986e-a6f9-48ec-af64-b68642e566b4" />
<img width="1737" height="195" alt="Capture d&#39;écran 2025-11-03 162024" src="https://github.com/user-attachments/assets/a143d6cd-466d-4d02-b944-7057fd56d4cc" />
<img width="1911" height="575" alt="image" src="https://github.com/user-attachments/assets/8913513f-110e-4835-8acd-7bc599ee995e" />
<img width="1718" height="844" alt="image" src="https://github.com/user-attachments/assets/98acb266-edd9-4900-b799-58bea0f29e86" />

## 7. Schéma L7 :

<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/eb040785-f0ff-45d1-aba8-df1df65f41b9" />


