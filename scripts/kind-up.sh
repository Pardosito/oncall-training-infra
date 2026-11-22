#!/usr/bin/env bash
# Local cluster for the mock system and the injector (ARCHITECTURE §14, INF-103/104):
#   create kind cluster `oncall-training` (CALICO=1: no default CNI + pinned Calico, so
#   NetworkPolicies are enforced) → build both images → kind load → apply k8s/overlays/local
#   → wait for the rollouts.
# Every kubectl call uses the kind context explicitly, so this never touches EKS.
# The injector expects the backend's docker-compose (LocalStack + Redis) on the host.
set -euo pipefail

cd "$(dirname "$0")/.."
NAME="${KIND_CLUSTER:-oncall-training}"
CTX="kind-$NAME"
CALICO_VERSION="v3.31.2"
k() { kubectl --context "$CTX" "$@"; }

reused=""
if kind get clusters 2>/dev/null | grep -qx "$NAME"; then
  echo "== kind cluster $NAME already exists; reusing it" >&2
  reused=1
else
  echo "== creating kind cluster $NAME${CALICO:+ (Calico $CALICO_VERSION)}" >&2
  config="$(mktemp)"
  trap 'rm -f "$config"' EXIT
  {
    echo "kind: Cluster"
    echo "apiVersion: kind.x-k8s.io/v1alpha4"
    if [ -n "${CALICO:-}" ]; then
      echo "networking:"
      echo "  disableDefaultCNI: true"
      # Not Calico's default 192.168.0.0/16: Docker Desktop's host (host.docker.internal) is
      # 192.168.65.254, and Calico would route it as pod traffic. Calico reads this from kubeadm.
      echo "  podSubnet: 10.244.0.0/16"
    fi
  } >"$config"
  kind create cluster --name "$NAME" --config "$config" --wait 120s
  if [ -n "${CALICO:-}" ]; then
    k apply -f "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml"
    k -n kube-system rollout status ds/calico-node --timeout=300s
  fi
fi

# Native platform (kind's node matches the host), unlike images-build (linux/amd64 for EKS).
for svc in mock-system injector; do
  echo "== building oncall-training/$svc:local" >&2
  docker build -q -f "services/$svc/Dockerfile" -t "oncall-training/$svc:local" . >/dev/null
  kind load docker-image --name "$NAME" "oncall-training/$svc:local"
done

echo "== applying k8s/overlays/local" >&2
kustomize build k8s/overlays/local | k apply -f -
# Same tag every build: on a reused cluster, restart so the pods pick up the image just loaded.
if [ -n "$reused" ]; then
  k -n mock rollout restart deploy
  k -n injector rollout restart deploy/injector
fi
for d in mock/gateway mock/orders mock/worker-svc injector/injector; do
  k -n "${d%/*}" rollout status "deploy/${d#*/}" --timeout=180s
done

echo >&2
echo "kind cluster $NAME is up (context $CTX). Next:" >&2
echo "  make local-smoke    # fault in, system down, revive (needs the backend's docker-compose up)" >&2
echo "  make kind-down      # delete the cluster" >&2
