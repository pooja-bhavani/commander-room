#!/usr/bin/env bash
# Writes one kubeconfig per agent, each tied to its own least-privilege
# ServiceAccount (see k8s/rbac.yaml), then proves what each one can and cannot do.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl config use-context kind-commander-room >/dev/null

server=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
ca=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

write_kubeconfig() {
  local account="$1" dir="agents/$1"
  mkdir -p "$dir"
  local token
  token=$(kubectl -n shop create token "$account" --duration=96h)
  umask 077
  cat > "$dir/kubeconfig" <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: commander-room
    cluster:
      server: $server
      certificate-authority-data: $ca
users:
  - name: $account
    user:
      token: $token
contexts:
  - name: $account
    context:
      cluster: commander-room
      user: $account
      namespace: shop
current-context: $account
KUBECONFIG
  chmod 600 "$dir/kubeconfig"
  echo "wrote $dir/kubeconfig (token valid 96h)"
}

can() { # kubeconfig, expected, args...
  local cfg="$1" expected="$2"; shift 2
  local got
  got=$(kubectl --kubeconfig "$cfg" auth can-i "$@" 2>/dev/null || true)
  printf '  %-4s (expected %-3s)  can-i %s\n' "$got" "$expected" "$*"
}

write_kubeconfig inspector
write_kubeconfig release

echo "inspector:"
K=agents/inspector/kubeconfig
can $K yes get pods
can $K yes get pods --subresource=log
can $K no  delete pods
can $K no  patch deployments/checkout
can $K no  get secrets
echo "release:"
K=agents/release/kubeconfig
can $K yes patch deployments/checkout
can $K no  delete pods
can $K no  get secrets
can $K no  create deployments
