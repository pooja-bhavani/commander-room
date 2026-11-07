#!/usr/bin/env bash
# Creates the real single-node kind cluster that the incident room watches.
set -euo pipefail
for tool in docker kind kubectl; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "docker is not running (or this user cannot use it)" >&2; exit 1; }

if kind get clusters | grep -qx commander-room; then
  echo "cluster commander-room already exists"
else
  kind create cluster --name commander-room --wait 120s
fi
kubectl config use-context kind-commander-room
kubectl get nodes
