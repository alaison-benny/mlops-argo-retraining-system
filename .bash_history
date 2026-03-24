curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
minikube start --driver=docker
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.4/install.yaml
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.5.4/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv ./argo-linux-amd64 /usr/local/bin/argo
vim train.py
vim train-workflow.yaml
clear
sudo systemctl start docker
docker status
sudo docker status
systemctl status docker
clear
minikube start --driver=docker
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      containers:
      - name: mlflow
        image: ghcr.io/mlflow/mlflow:latest
        command: ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000"]
        ports:
        - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow-service
spec:
  selector:
    app: mlflow
  ports:
    - protocol: TCP
      port: 5000
      targetPort: 5000
  type: ClusterIP
EOF

kubectl get svc mlflow-service
cat <<EOF > train-workflow.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: ml-training-pipeline-
  namespace: argo
spec:
  entrypoint: ml-pipeline
  templates:
  - name: ml-pipeline
    dag:
      tasks:
      - name: train-model
        template: trainer

  - name: trainer
    container:
      image: mlops-api:v3
      command: ["python3"]
      args: ["train.py"]
      env:
      - name: MLFLOW_TRACKING_URI
        value: "http://10.100.15.16:5000"
      - name: MLFLOW_HTTP_HEADER_HOST
        value: "10.100.15.16"
EOF

argo submit --watch train-workflow.yaml -n argo
clear
docker login -u alaisonbenny
argo submit --watch train-workflow.yaml -n argo
docker build -t mlops-api:v3 .
clear
cat <<EOF > train.py
import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestRegressor
import pandas as pd

if __name__ == "__main__":
    mlflow.set_experiment("MLOps_Project")
    with mlflow.start_run():
        # ഒരു സിമ്പിൾ മോഡൽ ട്രെയിനിംഗ്
        df = pd.DataFrame({"a": [1, 2], "b": [3, 4]})
        model = RandomForestRegressor()
        model.fit(df, [0, 1])
        mlflow.log_param("model_type", "RandomForest")
        mlflow.sklearn.log_model(model, "model")
        print("Training Completed and Logged to MLflow!")
EOF

docker build -t mlops-api:v3 .
cat <<EOF > Dockerfile
FROM python:3.9-slim

WORKDIR /app

# ആവശ്യമായ ലൈബ്രറികൾ ഇൻസ്റ്റാൾ ചെയ്യാൻ
RUN pip install mlflow pandas scikit-learn

# നമ്മുടെ ട്രെയിനിംഗ് സ്ക്രിപ്റ്റ് ഇതിലേക്ക് കോപ്പി ചെയ്യുക
COPY train.py .

# റൺ ചെയ്യാനുള്ള കമാൻഡ്
CMD ["python", "train.py"]
EOF

ls -a
cat <<EOF > .dockerignore
# Python temporary files
__pycache__/
*.py[cod]
*$py.class

# Environment files
.env
.venv
env/
venv/
ENV/

# Git files
.git/
.gitignore

# MLflow files (നമ്മൾ ലോക്കലിൽ റൺ ചെയ്തിട്ടുണ്ടെങ്കിൽ)
mlruns/
mlflow.db

# Docker files
Dockerfile
.dockerignore
EOF

ls
ls -a
clear
docker build -t mlops-api:v3 .
clear
docker ps
clear
docker build -t mlops-api:v3 .
minikube image load mlops-api:v3
claer
clear
argo delete ml-training-pipeline-rhr5r -n argo
argo submit --watch train-workflow.yaml -n argo
kubectl create clusterrolebinding argo-default-admin --clusterrole=admin --serviceaccount=argo:default --namespace=argo
argo delete ml-training-pipeline-zzrwk -n argo
clear
argo submit --watch train-workflow.yaml -n argo
argo logs ml-training-pipeline-j5ctw-trainer-969151875 -n argo
clear
argo list -n argo
argo logs ml-training-pipeline-j5ctw -n argo
kubectl create namespace argo-events
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml
cat <<EOF > minio-event-source.yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: minio
  namespace: argo-events
spec:
  minio:
    example:
      bucket:
        name: input-data
      endpoint: minio:9000
      events:
        - s3:ObjectCreated:Put
        - s3:ObjectCreated:Post
      insecure: true
      accessKey:
        key: accesskey
        name: artifacts-minio
      secretKey:
        key: secretkey
        name: artifacts-minio
EOF

kubectl apply -f minio-event-source.yaml
cat <<EOF > minio-sensor.yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: minio-sensor
  namespace: argo-events
spec:
  template:
    serviceAccountName: argo-events-sa
  dependencies:
    - name: test-dep
      eventSourceName: minio
      eventName: example
  triggers:
    - template:
        name: argo-workflow-trigger
        k8s:
          group: argoproj.io
          version: v1alpha1
          resource: workflows
          operation: create
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: ml-training-pipeline-auto-
              spec:
                # ഇവിടെ ചേട്ടായിയുടെ പഴയ train-workflow.yaml-ലെ spec ഭാഗം വരും
                arguments:
                  parameters:
                    - name: message
                      value: "New data detected in MinIO"
EOF

kubectl apply -f minio-sensor.yaml
kubectl create sa argo-events-sa -n argo-events
kubectl create clusterrolebinding argo-events-sa-role --clusterrole=admin --serviceaccount=argo-events-sa:argo-events-sa --namespace=argo-events
cat <<EOF > minio-sensor.yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: minio-sensor
  namespace: argo-events
spec:
  template:
    serviceAccountName: argo-events-sa
  dependencies:
    - name: minio-dep
      eventSourceName: minio
      eventName: example
  triggers:
    - template:
        name: argo-workflow-trigger
        k8s:
          group: argoproj.io
          version: v1alpha1
          resource: workflows
          operation: create
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: ml-training-auto-
                namespace: argo
              spec:
                entrypoint: ml-pipeline
                templates:
                - name: ml-pipeline
                  steps:
                  - - name: train-model
                      template: trainer
                - name: trainer
                  container:
                    image: mlops-api:v3
                    imagePullPolicy: IfNotPresent
EOF

kubectl apply -f minio-sensor.yaml
argo list -n argo
kubectl logs -n argo-events -l sensor-name=minio-sensor
kubectl get secret artifacts-minio -n argo-events
kubectl get secret artifacts-minio -n argo -o yaml | sed 's/namespace: argo/namespace: argo-events/' | kubectl apply -f -
claer
clear
kubectl create secret generic artifacts-minio --from-literal=accesskey=minioadmin --from-literal=secretkey=minioadmin -n argo-events
kubectl create secret generic artifacts-minio --from-literal=accesskey=minioadmin --from-literal=secretkey=minioadmin -n argo
kubectl get secrets -n argo-events
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get eventsource -n argo-events
kubectl get pods -n argo-events
kubectl delete pod minio-eventsource-zd446-5cb5dc8c8f-dbzqx -n argo-events
kubectl get pods -n argo-events
clear
kubectl delete pod minio-eventsource-zd446-5cb5dc8c8f-dbzqx -n argo-events
kubectl get pods -n argo-events
argo list -n argo
clear
kubectl logs -n argo-events minio-eventsource-zd446-5cb5dc8c8f-q4tfq
kubectl delete eventsource minio -n argo-events
kubectl delete sensor minio-sensor -n argo-events
kubectl apply -f minio-event-source.yaml
kubectl apply -f minio-sensor.yaml
claer
clear
kubectl get svc -A | grep minio
kubectl get svc -A
kubectl get svc -A | grep 9000
cat <<EOF > minio-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: minio-service
  namespace: default
spec:
  selector:
    # ഇവിടെ പോഡിന്റെ ശരിക്കുള്ള ലേബൽ വേണം. മിക്കവാറും 'app: minio' ആയിരിക്കും.
    app: minio 
  ports:
    - protocol: TCP
      port: 9000
      targetPort: 9000
EOF

kubectl apply -f minio-service.yaml
\cat <<EOF > minio-event-source.yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: minio
  namespace: argo-events
spec:
  minio:
    example:
      bucket:
        name: input-data
      # പുതിയ സർവീസ് അഡ്രസ്സ് ഇവിടെ നൽകുന്നു
      endpoint: minio-service.default.svc:9000 
      events:
        - s3:ObjectCreated:Put
        - s3:ObjectCreated:Post
      insecure: true
      accessKey:
        key: accesskey
        name: artifacts-minio
      secretKey:
        key: secretkey
        name: artifacts-minio
EOF

kubectl apply -f minio-event-source.yaml\\\\\\\\\\\\\\\\\\
clear
cat <<EOF > minio-event-source.yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: minio
  namespace: argo-events
spec:
  minio:
    example:
      bucket:
        name: input-data
      # പുതിയ സർവീസ് അഡ്രസ്സ് ഇവിടെ നൽകുന്നു
      endpoint: minio-service.default.svc:9000 
      events:
        - s3:ObjectCreated:Put
        - s3:ObjectCreated:Post
      insecure: true
      accessKey:
        key: accesskey
        name: artifacts-minio
      secretKey:
        key: secretkey
        name: artifacts-minio
EOF

kubectl apply -f minio-event-source.yaml
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get pods -n default --show-labels
clear
cat <<EOF > minio-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: minio-service
  namespace: default
spec:
  selector:
    app: mlflow
  ports:
    - protocol: TCP
      port: 9000
      targetPort: 9000
EOF

kubectl apply -f minio-service.yaml
cat <<EOF > minio-event-source.yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: minio
  namespace: argo-events
spec:
  minio:
    example:
      bucket:
        name: input-data
      endpoint: minio-service.default.svc:9000
      events:
        - s3:ObjectCreated:Put
        - s3:ObjectCreated:Post
      insecure: true
      accessKey:
        key: accesskey
        name: artifacts-minio
      secretKey:
        key: secretkey
        name: artifacts-minio
EOF

kubectl apply -f minio-event-source.yaml
kubectl get pods -n argo-events
clear
kubectl delete eventsource minio -n argo-events
kubectl delete sensor minio-sensor -n argo-events
cat <<EOF > minio-event-source.yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: minio
  namespace: argo-events
spec:
  minio:
    example:
      bucket:
        name: input-data
      endpoint: minio-service.default.svc:9000
      events:
        - s3:ObjectCreated:Put
        - s3:ObjectCreated:Post
      insecure: true
      accessKey:
        key: accesskey
        name: artifacts-minio
      secretKey:
        key: secretkey
        name: artifacts-minio
EOF

kubectl apply -f minio-event-source.yaml
cat <<EOF > minio-sensor.yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: minio-sensor
  namespace: argo-events
spec:
  template:
    serviceAccountName: argo-events-sa
  dependencies:
    - name: minio-dep
      eventSourceName: minio
      eventName: example
  triggers:
    - template:
        name: argo-workflow-trigger
        k8s:
          group: argoproj.io
          version: v1alpha1
          resource: workflows
          operation: create
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: ml-training-auto-
                namespace: argo
              spec:
                entrypoint: ml-pipeline
                templates:
                - name: ml-pipeline
                  steps:
                  - - name: train-model
                      template: trainer
                - name: trainer
                  container:
                    image: mlops-api:v3
                    imagePullPolicy: IfNotPresent
EOF

kubectl apply -f minio-sensor.yaml
kubectl get pods -n argo-events
clear
whoami
pwd
sudo apt update && sudo apt upgrade -y
sudo apt install python3-pip python3-venv -y
python3 -m venv venv
source venv/bin/activate
sudo apt install docker.io -y
sudo usermod -aG docker $USER && newgrp docker
clear
ls
vim minio-sensor.yaml
kubectl apply -f minio-sensor.yaml
minikube start
source venv/bin/activate
minikube start
kubectl get nodes
kubectl apply -f minio-service.yaml
kubectl apply -f minio-event-source.yaml
kubectl apply -f minio-sensor.yaml
cat minio-event-source.yaml
kubectl delete pod -n argo-events -l event-source-name=minio
clear
kubectl get pods -n argo-events
kubectl logs -n argo-events minio-eventsource-884hn-785d6b8f49-vmlxl
kubectl get svc -n default minio-service
clear
kubectl get pod -n default -l app=mlflow -o jsonpath='{.items[0].spec.containers[*].ports[*].containerPort}'
kubectl patch svc minio-service -n default --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value":5000}, {"op": "replace", "path": "/spec/ports/0/port", "value":5000}]'
sed -i 's/9000/5000/g' minio-event-source.yaml
kubectl apply -f minio-event-source.yaml
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get pods
kubectl get pods -n argo-events
kubectl logs -n argo-events minio-eventsource-884hn-5ff69596bf-2bk58
clear
kubectl delete secret artifacts-minio -n argo-events
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minioadmin --from-literal=secretkey=minioadmin
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get pods -n argo-events
kubectl logs -n argo-events minio-eventsource-884hn-5ff69596bf-2bk58
clear
kubectl get pod -n default -l app=mlflow -o yaml | grep -iE "MINIO_ACCESS_KEY|MINIO_SECRET_KEY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY"
kubectl get secrets -n default
kubectl get configmaps -n default
kubectl get sa -n default
sudo kubectl get secrets -n default
clear
kubectl logs -n default -l app=mlflow --tail=50
kubectl exec -n default -it $(kubectl get pods -n default -l app=mlflow -o jsonpath='{.items[0].metadata.name}') -- env
clear
kubectl patch svc minio-service -n default --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value":9000}, {"op": "replace", "path": "/spec/ports/0/port", "value":9000}]'
kubectl delete secret artifacts-minio -n argo-events
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minio --from-literal=secretkey=minio123
sed -i 's/5000/9000/g' minio-event-source.yaml
kubectl apply -f minio-event-source.yaml
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get pods -n argo-events
clear
kubectl exec -n default -it $(kubectl get pods -n default -l app=mlflow -o jsonpath='{.items[0].metadata.name}') -- cat /app/config.yaml 2>/dev/null || kubectl exec -n default -it $(kubectl get pods -n default -l app=mlflow -o jsonpath='{.items[0].metadata.name}') -- ls -R /app
clear
kubectl exec -it $(kubectl get pods -l app=mlflow -o jsonpath='{.items[0].metadata.name}') -- ls -F /
cat Dockerfile
clear
kubectl get pod -l app=mlflow -o jsonpath='{.status.containerStatuses[0].image}'
kubectl describe pod -l app=mlflow | grep -i "Args" -A 5
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minioadmin --from-literal=secretkey=minioadmin
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get pods -n argo-events
kubectl get pods -n argo-events minio-eventsource-884hn-785d6b8f49-22sfc
kubectl logs argo-events minio-eventsource-884hn-785d6b8f49-22sfc
kubectl delete secret artifacts-minio -n argo-events
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minioadmin --from-literal=secretkey=minioadmin
grep "endpoint" minio-event-source.yaml
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get pods -n argo-events
clear
kubectl delete pod -n argo-events -l event-source-name=minio --force --grace-period=0
kubectl get pods -n argo-events -w
kubectl delete eventsource minio -n argo-events
vim minio-event-source.yaml
kubectl get pods -n argo-events
kubectl apply -f minio-event-source.yaml
kubectl get pods -n argo-events -l event-source-name=minio
kubectl get pods -n argo-events
kubectl logs minio-eventsource-5pp44-785d6b8f49-s6m2h
clear
kubectl logs -n argo-events -l event-source-name=minio --tail=20
kubectl delete secret artifacts-minio -n argo-events
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minio --from-literal=secretkey=minio123
kubectl get svc minio-service -n default
kubectl get pods -n argo-events
kubectl run minio-cli --image=minio/mc --env="MC_HOST_minio=http://minio:minio123@minio-service.default.svc:9000" --restart=Never -- mb minio/input-data
kubectl delete pod -n argo-events -l event-source-name=minio
kubectl get pods -n argo-events -l event-source-name=minio
clear
ls
source venv/bin/activate
kubectl get pods -A
clear
minikube start
kubectl get nodes
souce venv/bin/activate
clear
source venv/bin/activate
minikube start
kubectl get nodes
kubectl get nodes -a
kubectl get nodes -A
kubectl get nodes
clear
kubectl run minio-checker --image=minio/mc --rm -it --restart=Never -- mc ls --insecure minio --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
clera
clear
kubectl run minio-checker --image=minio/mc --rm -it --restart=Never -- mc ls --insecure minio --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
kubectl run minio-create-bucket --image=minio/mc --rm -it --restart=Never -- mc mb --insecure minio/input-data --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
clear
kubectl run minio-test-bucket --image=minio/mc --restart=Never -- mc mb --insecure minio/input-data --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
kubectl logs minio-test-bucket
kubectl delete eventsource minio -n argo-events
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minio --from-literal=secretkey=minio123
kubectl delete secret artifacts-minio -n argo-events
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minio --from-literal=secretkey=minio123
kubectl apply -f minio-event-source.yaml
kubectl get pods -n argo-events -w
clear
kubectl logs minio-eventsource-9sr4h-785d6b8f49-f7lh8 -n argo-events
kubectl get secret artifacts-minio -n argo-events -o yaml
kubectl run tmp-shell --rm -i --tty --image=busybox -- sh
wget -O- http://minio-service.default.svc:9000
clear
source venv/bin/activate
kubectl run tmp-shell --rm -i --tty --image=busybox -- sh
wget -O- http://minio-service:9000
wget -O- http://minio-service.default.svc.cluster.local:9000
cd scripts
vim scripts/port-forward-minio.sh
mkdir -p scripts
vim scripts/port-forward-minio.sh
chmod +x scripts/port-forward-minio.sh
./scripts/port-forward-minio.sh
clear
source /venv/bin/activate
source venv/bin/activate
clear
kubectl get pods -n default
kubectl logs minio-cli -n default
kubectl logs minio-test-bucketi -n default
kubectl get svc -n default
wget -O- http://minio-service.default.svc:9000
clear
vim minio-deployment.yaml
kubectl apply -f minio-deployment.yaml
kubectl get pods -n default
kubectl get svc -n default
kubectl logs minio-cli -n default
kubectl logs minio-test-bucket -n default
kubectl run tmp-shell --rm -i --tty --image=busybox -- sh
wget -O- http://minio-service.default.svc:9000
kubectl delete pod tmp-shell -n default
kubectl run tmp-shell --rm -i --tty --image=busybox -- sh
clear
ls
cat minio-service.yaml
vim minio-service.yaml
kubectl apply -f infra/minio-service.yaml
ls -a
source venv/bin/activate
kubectl apply -f minio-service.yaml
kubectl get svc -n default
curl ifconfig.me
clear
source venv/bin/activate
clear
ls
kubectl apply -f minio-service.yaml
ls ~
kubectl get svc -n default
kubectl get nodes -n default
kubectl get nodes -a
kubectl get nodes -A
kubectl get nodes
kubectl get pods -n default
clear
kubectl get pods -n default
kubectl logs minio-cli -n default
kubectl logs minio-test-bucket -n default
kubectl describe pod minio-cli -n default
clear
kubectl run check-now --image=minio/mc --rm -it --restart=Never -- mc ls --insecure minio --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
kubectl run create-now --image=minio/mc --rm -it --restart=Never -- mc mb --insecure minio/input-data --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
kubectl delete pod minio-cli
clear
kubectl get pods -n argo-events
kubectl logs minio-eventsource-9sr4h-785d6b8f49-f7lh8 -n argo-events
clear
kubectl run mc-check --image=minio/mc --rm -it --restart=Never -- mc ls --insecure minio --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
kubectl run mc-test-log --image=minio/mc --restart=Never -- mc ls --insecure minio --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
kubectl logs mc-test-log
kubectl run force-create --image=minio/mc --rm -it --restart=Never -- mc mb --insecure minio/input-data --address http://minio-service.default.svc:9000 --access-key minio --secret-key minio123
clear
kubectl get svc -A | grep minio
kubectl logs -l app=minio -n default
kubectl run create-bucket-final --image=minio/mc --rm -it --restart=Never --   mc mb --insecure minio/input-data --address http://minio-service.default.svc:9000   --access-key minioadmin --secret-key minioadmin
kubectl delete eventsource minio -n argo-events
kubectl apply -f minio-event-source.yaml
kubectl run create-bucket-final --image=minio/mc --rm -it --restart=Never --   mc mb --insecure minio/input-data --address http://minio-service.default.svc:9000   --access-key minioadmin --secret-key minioadmin
clear
kubectl run create-ip-test --image=minio/mc --rm -it --restart=Never --   mc mb --insecure minio/input-data --address http://10.244.0.76:9000   --access-key minioadmin --secret-key minioadmin
kubectl rollout restart deployment minio -n default
kubectl get pods -l app=minio -o wide
kubectl get pods -n argo-events
echo "id,data,label" > training_data.csv
echo "1,0.99,1" >> training_data.csv
kubectl run manual-upload --image=minio/mc --rm -it --restart=Never -- mc cp --insecure training_data.csv minio/input-data --address http://10.244.0.87:9000 --access-key minioadmin --secret-key minioadmin
kubectl get workflows -n argo-events
clear
kubectl logs -l sensor-name=minio-sensor -n argo-events
kubectl run check-notif --image=minio/mc --rm -it --restart=Never -- mc event list --insecure minio/input-data --address http://10.244.0.87:9000 --access-key minioadmin --secret-key minioadmin
argo list -A
kubectl get workflows -A
kubectl run ls-check --image=minio/mc --rm -it --restart=Never -- mc ls --insecure minio/input-data --address http://10.244.0.87:9000 --access-key minioadmin --secret-key minioadmin
kubectl port-forward svc/minio-service 9000:9000 -n default
source venv/bin/activate
clear
echo "id,data,label" > training_data.csv
kubectl run manual-upload --image=minio/mc --rm -it --restart=Never -- mc cp --insecure training_data.csv minio/input-data --address http://127.0.0.1:9000 --access-key minioadmin --secret-key minioadmin
kubectl run check-notif --image=minio/mc --rm -it --restart=Never -- mc event list --insecure minio/input-data --address http://127.0.0.1:9000 --access-key minioadmin --secret-key minioadmin
kubectl run final-upload-test --image=minio/mc --rm -it --restart=Never -- mc cp --insecure training_data.csv minio/input-data --address http://minio-service.default.svc:9000 --access-key minioadmin --secret-key minioadmin
kubectl get workflows -n argo-events
clear
kubectl get pods -n default
kubectl exec -it minio-54d7b6c4db-7kxvj -n default -- /bin/sh
kubectl get pod minio-54d7b6c4db-7kxvj -n default -o jsonpath='{.spec.containers[0].env}' | jq
clear
kubectl exec -it minio-54d7b6c4db-7kxvj -n default -- /bin/sh
kubectl get workflows -n argo-events
kubectl delete secret artifacts-minio -n argo-events 2>/dev/null
kubectl create secret generic artifacts-minio --namespace argo-events --from-literal=accesskey=minio --from-literal=secretkey=minio123
kubectl delete eventsource minio -n argo-events
kubectl apply -f minio-event-source.yaml
kubectl exec -it minio-54d7b6c4db-7kxvj -n default -- /bin/sh
clear
kubectl get workflows -n argo-events
kubectl delete secret artifacts-minio -n argo-events
kubectl create secret generic artifacts-minio -n argo-events --from-literal=accesskey=minio --from-literal=secretkey=minio123
vim minio-event-source.yaml
kubectl apply -f minio-event-source.yaml -n argo-events
kubectl exec -it minio-54d7b6c4db-7kxvj -n default -- /bin/sh
clear
kubectl get workflows -n argo-events
kubectl logs -l sensor-name=minio-sensor -n argo-events --tail=20
kubectl create rolebinding sensor-workflow-creator --namespace=argo --clusterrole=argo-cluster-role --serviceaccount=argo-events:argo-events-sa
kubectl exec minio-54d7b6c4db-7kxvj -n default -- mc cp /tmp/data.csv local/input-data/final_trigger.csv --insecure
kubectl get workflows -n argo
eval $(minikube docker-env)
docker build -t mlops-api:v3 .
ls
vim minio-sensor.yaml
cat minio-sensor.yaml
vim minio-sensor.yaml
kubectl delete sensor minio-sensor -n argo-events
kubectl apply -f minio-sensor.yaml -n argo-events
clear
kubectl get workflows -n argo
kubectl apply -f minio-sensor.yaml -n argo-events
kubectl exec minio-54d7b6c4db-7kxvj -n default -- mc cp /tmp/data.csv local/input-data/trigger_v4.csv --insecure
kubectl get workflows -n argo
clear
kubectl get workflows -n argo --watch
minikube service argo-server -n argo --url
kubectl port-forward deployment/argo-server -n argo 2746:2746
kubectl port-forward deployment/argo-server -n argo --address 0.0.0.0 2746:2746
# അർഗോയുടെ സീക്രട്ട് ടോക്കൺ കാണാൻ ഇത് അടിക്കുക
kubectl -n argo get secret $(kubectl -n argo get sa argo-server -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode
# അർഗോയുടെ സീക്രട്ട് ടോക്കൺ കാണാൻ ഇത് അടിക്കുക
kubectl -n argo get secret $(kubectl -n argo get sa argo-server -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode
arv -n argo auth token
kubectl patch deployment argo-server -n argo --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["server", "--auth-mode", "server"]}]'
kubectl port-forward deployment/argo-server -n argo --address 0.0.0.0 2746:2746
clear
github --version
git ---version
git --version
clear
git config --global user.name "alaison-benny"
git config --global user.email "alisaalaison@gmail.com"
mkdir -p .github/workflows
vim .github/workflows/deploy.yml
source venv/bin/activate
clear
vim .gitignore
