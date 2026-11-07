#!/usr/bin/env bash
# Builds checkout v1, loads it into the cluster and deploys it: the healthy baseline.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl config use-context kind-commander-room >/dev/null

docker build --build-arg VERSION=v1 -t checkout:v1 app
kind load docker-image checkout:v1 --name commander-room

kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/rbac.yaml
kubectl -n shop rollout status deployment/checkout --timeout=120s
kubectl -n shop get pods -o wide
