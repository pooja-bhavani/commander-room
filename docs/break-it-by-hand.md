# Breaking the service by hand

These are the commands the demo types. They are the same steps as `scripts/03-release-v2.sh`.

```bash
kubectl config use-context kind-commander-room
grep -n "cache" app/v2/server.py                 # v2 preloads a 300 MB price cache
docker build --build-arg VERSION=v2 -t checkout:v2 app
kind load docker-image checkout:v2 --name commander-room
kubectl -n shop set image deployment/checkout checkout=checkout:v2
kubectl -n shop annotate deployment/checkout --overwrite \
  kubernetes.io/change-cause="release v2: preload price cache at startup"
kubectl -n shop get pods -w                      # new pod ends in CrashLoopBackOff
```

Pods are limited to 128Mi, so the kernel kills v2 at startup (OOMKilled, exit code 137).
The two v1 pods keep serving while the rollout stalls.

What each agent may do on the cluster:

```bash
kubectl --kubeconfig agents/inspector/kubeconfig auth can-i --list -n shop
kubectl --kubeconfig agents/release/kubeconfig   auth can-i --list -n shop
```
