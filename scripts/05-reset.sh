#!/usr/bin/env bash
# Puts the cluster back to the healthy v1 baseline, for another run.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl config use-context kind-commander-room >/dev/null
kubectl apply -f k8s/deployment.yaml
kubectl -n shop rollout status deployment/checkout --timeout=120s
kubectl -n shop get pods
