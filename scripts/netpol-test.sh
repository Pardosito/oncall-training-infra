#!/usr/bin/env bash
# Checks the NetworkPolicies (ARCHITECTURE §5.3) on kind with Calico (INF-075..078):
# allowed paths answer, denied paths time out, and kubelet probes still keep every pod Ready.
# Two throwaway probe pods (in `app` and `default`) stand in for the backend, which runs on
# the host locally. ALB → backend-api (allow-alb-to-api) needs EKS: INF-067.
set -euo pipefail

CTX="kind-${KIND_CLUSTER:-oncall-training}"
IMAGE="oncall-training/mock-system:local" # has node, used for fetch()
k() { kubectl --context "$CTX" "$@"; }
fail() { echo "error: $*" >&2; exit 1; }

k get ns mock >/dev/null 2>&1 || fail "no kind cluster ($CTX); run make kind-up CALICO=1"
k -n kube-system get ds calico-node >/dev/null 2>&1 \
  || fail "kind's default CNI doesn't enforce NetworkPolicies; recreate with: make kind-down && make kind-up CALICO=1"
k -n mock get networkpolicy default-deny-ingress >/dev/null 2>&1 || fail "no policies in mock; run make kind-up"

cleanup() { for ns in app default; do k -n "$ns" delete pod netpol-probe --ignore-not-found --wait=false >/dev/null 2>&1 || true; done; }
trap cleanup EXIT
for ns in app default; do
  k -n "$ns" delete pod netpol-probe --ignore-not-found >/dev/null
  k -n "$ns" run netpol-probe --image="$IMAGE" --image-pull-policy=Never --restart=Never \
    --labels=app.kubernetes.io/name=netpol-probe --command -- node -e 'setTimeout(() => {}, 600000)' >/dev/null
done
for ns in app default; do k -n "$ns" wait pod/netpol-probe --for=condition=Ready --timeout=60s >/dev/null; done

injector_ip="$(k -n injector get pod -l app.kubernetes.io/name=injector -o jsonpath='{.items[0].status.podIP}')"

# reach <namespace> <pod|deploy/name> <url> → "open" (any HTTP answer) or "blocked" (timeout)
reach() {
  k -n "$1" exec "$2" -- node -e \
    'fetch(process.argv[1], { signal: AbortSignal.timeout(3000) }).then(() => console.log("open"), () => console.log("blocked"))' \
    "$3" 2>/dev/null || echo "exec-failed"
}

failures=0
check() { # check <want> <description> <namespace> <pod> <url>
  local want="$1" what="$2" got
  got="$(reach "$3" "$4" "$5")"
  if [ "$got" = "$want" ]; then
    printf '  ok    %-52s %s\n' "$what" "$got"
  else
    printf '  FAIL  %-52s got %s, want %s\n' "$what" "$got" "$want"
    failures=$((failures + 1))
  fi
}

echo "== allowed"
check open "app → mock gateway:8080 (allow-from-app)" app netpol-probe http://gateway.mock.svc.cluster.local:8080/health
check open "app → mock orders:8080 (allow-from-app)" app netpol-probe http://orders.mock.svc.cluster.local:8080/health
check open "gateway → orders:8080 (allow-intra-mock)" mock deploy/gateway http://orders.mock.svc.cluster.local:8080/health
check open "orders → worker-svc:8080 (allow-intra-mock)" mock deploy/orders http://worker-svc.mock.svc.cluster.local:8080/health
echo "== denied"
check blocked "injector → mock gateway:8080" injector deploy/injector http://gateway.mock.svc.cluster.local:8080/health
check blocked "default ns → mock gateway:8080" default netpol-probe http://gateway.mock.svc.cluster.local:8080/health
check blocked "mock gateway → injector pod:8080" mock deploy/gateway "http://$injector_ip:8080/healthz"
check blocked "app → injector pod:8080" app netpol-probe "http://$injector_ip:8080/healthz"

echo "== kubelet probes (pods Ready, no restarts)"
for ns in mock injector; do
  bad="$(k -n "$ns" get pods -l app.kubernetes.io/part-of=oncall-training -o json \
    | jq -r '.items[] | select(([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) == 0
        or ([.status.containerStatuses[]?.restartCount] | add // 0) > 0) | .metadata.name')"
  if [ -z "$bad" ]; then
    printf '  ok    %-52s %s\n' "$ns pods Ready, 0 restarts" ok
  else
    printf '  FAIL  %-52s %s\n' "$ns pods not Ready or restarted" "$(tr '\n' ' ' <<<"$bad")"
    failures=$((failures + 1))
  fi
done

[ "$failures" -eq 0 ] || fail "$failures NetworkPolicy check(s) failed"
echo "netpol-test: ok"
