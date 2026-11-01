#!/usr/bin/env bash
# INF-074: checks the RBAC of ARCHITECTURE §5.2 on the current cluster, both what each
# service account may do and what it must not. Read-only (kubectl auth can-i).
set -euo pipefail

fail=0
check() { # expect sa-namespace sa verb resource namespace
  local expect="$1" sa="system:serviceaccount:$2:$3" got
  got="$(kubectl auth can-i "$4" "$5" -n "$6" --as="$sa" 2>/dev/null || true)"
  if [ "$got" = "$expect" ]; then
    printf '  ok    %-28s %-7s %-26s in %-8s → %s\n' "$2/$3" "$4" "$5" "$6" "$got"
  else
    printf '  FAIL  %-28s %-7s %-26s in %-8s → %s (expected %s)\n' "$2/$3" "$4" "$5" "$6" "$got" "$expect"
    fail=1
  fi
}

echo "backend-api (mock-reader)"
check yes app backend-api get pods mock
check yes app backend-api list deployments.apps mock
check yes app backend-api get pods/log mock
check no  app backend-api patch deployments.apps/scale mock
check no  app backend-api delete pods mock
check no  app backend-api list pods app

echo "backend-worker (mock-operator)"
check yes app backend-worker patch deployments.apps mock
check yes app backend-worker patch deployments.apps/scale mock
check yes app backend-worker get pods/log mock
check no  app backend-worker delete pods mock
check no  app backend-worker patch deployments.apps app

echo "injector (mock-injector)"
check yes injector injector patch deployments.apps/scale mock
check yes injector injector delete pods mock
check yes injector injector list pods mock
check no  injector injector delete pods app
check no  injector injector patch deployments.apps app
check no  injector injector delete deployments.apps mock
check no  injector injector get secrets mock

echo "mock services (no API access)"
check no mock mock-system list pods mock
check no mock default list pods mock

exit "$fail"
