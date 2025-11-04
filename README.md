# S5 — Persistance & workloads avec état (PostgreSQL StatefulSet)

## 1) Executive summary
Déployer **PostgreSQL** en **StatefulSet** avec volumes dynamiques (PVC/StorageClass) et exposer un **Service headless** pour l’identité stable.  
Livrer un **runbook** de **sauvegarde / restauration** :
- **Dump logique** (pg_dump/psql) — *suffit pour l’évaluation*.
- **Velero (optionnel)** avec backend S3 local **MinIO**.

---

## 2) Périmètre & prérequis

- Environnement : **WSL2 + Kind** (cluster local), `kubectl`, `helm` (si Velero via Helm), `psql` embarqué dans le conteneur.
- Namespace utilisé : **`workshop`** (créé s’il n’existe pas).
- **StorageClass** avec provisioning dynamique **obligatoire**.

### 2.1 Vérifier le storage dynamique
```bash
kubectl get sc
```
# ➜ choisir une SC (ex. local-path) ou créer "standard" et la marquer par défaut.
Recommandation : si tu as plusieurs “default”, n’en garde qu’une seule :

```bash
# exemple : garder local-path par défaut
kubectl annotate sc standard storageclass.kubernetes.io/is-default-class- --overwrite 2>/dev/null || true
```
3) Git & arborescence
```bash
git switch -c feat/s5-stateful-postgres
mkdir -p s5/k8s
```
Arbo :
```
s5/
 ├─ k8s/
 │   ├─ 10-pg-secret.yaml
 │   ├─ 20-pg-svc-headless.yaml
 │   └─ 30-pg-statefulset.yaml
 └─ README-S5.md
```
4) Manifests (corrigés & prêts à l’emploi)
Note StorageClass :

Si ta SC par défaut s’appelle local-path, tu peux soit supprimer la ligne storageClassName ci-dessous (laisser la default), soit la mettre à local-path.

Si tu veux forcer une SC spécifique : mets storageClassName: standard (ou autre nom exact).

4.1 Secret (mot de passe Postgres)
yaml
```
# s5/k8s/10-pg-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: pg-secret
  namespace: workshop
type: Opaque
stringData:
  POSTGRES_PASSWORD: supersecret
```
4.2 Service headless
yaml
```
# s5/k8s/20-pg-svc-headless.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: workshop
  labels:
    app: postgres
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - name: pg
      port: 5432
      targetPort: 5432
```
4.3 StatefulSet (+ PVC dynamiques via volumeClaimTemplates)
yaml
```
# s5/k8s/30-pg-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: workshop
spec:
  serviceName: postgres              # doit pointer sur le service headless
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16
          imagePullPolicy: IfNotPresent
          ports:
            - name: pg
              containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: pg-secret
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command: ["bash","-lc","pg_isready -U postgres"]
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            exec:
              command: ["bash","-lc","pg_isready -U postgres"]
            initialDelaySeconds: 20
            periodSeconds: 10
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 8Gi
        # Option 1: laisser la default (supprimer la ligne ci-dessous)
        storageClassName: standard
```
5) Déploiement
```
kubectl get ns workshop || kubectl create ns workshop

kubectl apply -f s5/k8s/10-pg-secret.yaml
kubectl apply -f s5/k8s/20-pg-svc-headless.yaml
kubectl apply -f s5/k8s/30-pg-statefulset.yaml

kubectl -n workshop rollout status sts/postgres
kubectl -n workshop get pods -l app=postgres -o wide
kubectl -n workshop get pvc
kubectl get pv
Attendu : un PVC data-postgres-0 Bound et un PV associé.
```
6) Test de persistance (données → redémarrage → données présentes)
```
POD=$(kubectl -n workshop get po -l app=postgres -o jsonpath='{.items[0].metadata.name}')
```
# 6.1 Créer des données
```
kubectl -n workshop exec -it "$POD" -- psql -U postgres -c "CREATE DATABASE s5;"
kubectl -n workshop exec -it "$POD" -- psql -U postgres -d s5 -c "CREATE TABLE demo(id int primary key, msg text);"
kubectl -n workshop exec -it "$POD" -- psql -U postgres -d s5 -c "INSERT INTO demo VALUES (1,'hello-persist');"
kubectl -n workshop exec -it "$POD" -- psql -U postgres -d s5 -c "SELECT * FROM demo;"
```
# 6.2 Redémarrer le pod
```
kubectl -n workshop delete pod "$POD"
kubectl -n workshop get pods -l app=postgres -w
```
# 6.3 Vérifier que les données persistent
```
POD=$(kubectl -n workshop get po -l app=postgres -o jsonpath='{.items[0].metadata.name}')
kubectl -n workshop exec -it "$POD" -- psql -U postgres -d s5 -c "SELECT * FROM demo;"
```
7) Runbook — Backup / Restore (dump logique) ✅ [recommandé pour l’évaluation]
7.1 Backup (dump)
```
POD=$(kubectl -n workshop get po -l app=postgres -o jsonpath='{.items[0].metadata.name}')
kubectl -n workshop exec -i "$POD" -- bash -lc 'pg_dumpall -U postgres' > s5/backup-$(date +%F-%H%M).sql

ls -lh s5/backup-*.sql
head -n 20 s5/backup-*.sql
```
7.2 Restore
```
# (simule une perte)
kubectl -n workshop exec -it "$POD" -- psql -U postgres -d s5 -c "DROP TABLE IF EXISTS demo;"

# restore complet
LATEST=$(ls -1t s5/backup-*.sql | head -n1)
kubectl -n workshop exec -i "$POD" -- psql -U postgres < "$LATEST"

# contrôle
kubectl -n workshop exec -it "$POD" -- psql -U postgres -d s5 -c "SELECT * FROM demo;"
Variante (copier dans le Pod) :
```
```
kubectl cp "$LATEST" workshop/"$POD":/tmp/backup.sql
kubectl -n workshop exec -it "$POD" -- bash -lc 'psql -U postgres < /tmp/backup.sql'
```
8) Runbook — Velero (optionnel)
Attention : Velero est optionnel. Le dump suffit pour l’éval.
Ci-dessous, parcours minimal qui fonctionne en local (Kind + MinIO sans Helm possible).

8.1 Déployer MinIO (S3 local) sans PVC — (YAML simple)
```
cat > /tmp/minio.yaml <<'YAML'
apiVersion: v1
kind: Namespace
metadata: { name: velero }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: velero
  labels: { app: minio }
spec:
  replicas: 1
  selector: { matchLabels: { app: minio } }
  template:
    metadata: { labels: { app: minio } }
    spec:
      containers:
        - name: minio
          image: minio/minio:latest
          args: ["server", "/data", "--console-address", ":9001"]
          env:
            - { name: MINIO_ROOT_USER, value: "minioadmin" }
            - { name: MINIO_ROOT_PASSWORD, value: "minioadmin" }
          ports:
            - { name: api, containerPort: 9000 }
            - { name: console, containerPort: 9001 }
          readinessProbe:
            httpGet: { path: /minio/health/ready, port: 9000 }
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /minio/health/live, port: 9000 }
            initialDelaySeconds: 10
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: velero
spec:
  selector: { app: minio }
  ports:
    - { name: api, port: 9000, targetPort: 9000 }
    - { name: console, port: 9001, targetPort: 9001 }
YAML
```
```
kubectl apply -f /tmp/minio.yaml
kubectl -n velero rollout status deploy/minio
```
Créer le bucket velero :

```
kubectl -n velero run mc --image=minio/mc --restart=Never -- bash -lc \
  "mc alias set minio http://minio.velero.svc.cluster.local:9000 minioadmin minioadmin && \
   mc mb -p minio/velero && mc ls minio"
kubectl -n velero delete pod mc
```
8.2 Installer Velero (client + serveur)
```
# Client
VELERO_VERSION=v1.13.2
curl -L -o velero.tar.gz https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz
tar -xzf velero.tar.gz && sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
velero version --client-only

# Credentials provider "aws" (MinIO)
cat > /tmp/velero-credentials <<'EOF'
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin
EOF

# Installation serveur (node-agent pour backup FS)
velero install \
  --namespace velero \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.2 \
  --bucket velero \
  --secret-file /tmp/velero-credentials \
  --backup-location-config s3Url=http://minio.velero.svc.cluster.local:9000,publicUrl=http://127.0.0.1:9000,region=minio,s3ForcePathStyle=true \
  --use-node-agent
```
```
kubectl -n velero get pods
velero version
kubectl api-resources | grep -i velero
```
8.3 Backup / Restore (Velero)
```
BK=workshop-$(date +%F-%H%M)
velero backup create "$BK" \
  --include-namespaces workshop \
  --default-volumes-to-fs-backup \
  --wait
velero backup describe "$BK" --details
velero backup logs "$BK"

# simulate loss
kubectl -n workshop delete statefulset postgres --cascade=orphan
kubectl -n workshop delete svc postgres

# restore
velero restore create --from-backup "$BK" --wait
kubectl -n workshop get sts,po,svc,pvc
```

9) Preuves (à capturer pour le rendu)
```

# Storage & volumes
kubectl get sc
kubectl -n workshop get pvc
kubectl get pv

# Workload
kubectl -n workshop get sts,po,svc -l app=postgres -o wide
kubectl -n workshop get endpoints postgres

# Persistance (après redémarrage)
kubectl -n workshop exec -it $(kubectl -n workshop get po -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
  psql -U postgres -d s5 -c "SELECT * FROM demo;"

# Backup/restore (dump)
ls -lh s5/backup-*.sql

```
<img width="2508" height="875" alt="Capture d&#39;écran 2025-11-04 102637" src="https://github.com/user-attachments/assets/44ec24f5-1eef-4da8-a804-42829027b2c3" />

10) Troubleshooting (flash)
PVC en Pending → pas de StorageClass par défaut / nom erroné dans storageClassName.

ReclaimPolicy :
```
Delete (local-path par défaut) : PV supprimé quand PVC supprimé.

Retain : PV conservé (restauration manuelle possible).

StatefulSet : supprimer un Pod ne supprime pas le PVC ; l’identité postgres-0 réutilise le volume.
```
Velero :
```
no matches for kind "Backup" → CRDs/pods Velero non installés.

Problèmes image pull MinIO → utiliser minio/minio (Docker Hub) + YAML simple ci-dessus.
```
11) Nettoyage
```
# App
kubectl delete -f s5/k8s/30-pg-statefulset.yaml
kubectl delete -f s5/k8s/20-pg-svc-headless.yaml
kubectl delete -f s5/k8s/10-pg-secret.yaml
kubectl -n workshop delete pvc --all   # si tu veux tout raser

# Velero/MinIO (si installés)
kubectl delete ns velero --ignore-not-found
```
12) shéma
<img width="1024" height="1024" alt="image" src="https://github.com/user-attachments/assets/7a4454af-104c-4867-93df-a9483384ed9c" />
<img width="1024" height="1024" alt="image" src="https://github.com/user-attachments/assets/955fb342-30ac-4d9a-bcca-3b057fb8cfd0" />



