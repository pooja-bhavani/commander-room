#!/usr/bin/env bash
# Rolls out checkout v2, which preloads a 300 MB price cache into pods limited
# to 128 MiB. The kernel kills the container (OOMKilled, exit 137), the new pods
# never become Ready and the rollout stalls while v1 keeps serving.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl config use-context kind-commander-room >/dev/null

docker build --build-arg VERSION=v2 -t checkout:v2 app
kind load docker-image checkout:v2 --name commander-room

kubectl -n shop set image deployment/checkout checkout=checkout:v2
kubectl -n shop annotate deployment/checkout --overwrite \
  kubernetes.io/change-cause="release v2: preload price cache at startup"

echo "waiting up to 45s to see whether the rollout finishes..."
kubectl -n shop rollout status deployment/checkout --timeout=45s || true
kubectl -n shop get pods
