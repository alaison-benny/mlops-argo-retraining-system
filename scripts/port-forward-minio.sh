#!/bin/bash
NAMESPACE=default
SERVICE=minio-service
LOCAL_PORT=9000
REMOTE_PORT=9000

echo "🚀 Starting port-forward for MinIO..."
kubectl port-forward svc/${SERVICE} ${LOCAL_PORT}:${REMOTE_PORT} -n ${NAMESPACE}

