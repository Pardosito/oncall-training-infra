#!/usr/bin/env bash
# kustomize build + kubeconform for the base and every overlay (CONVENTIONS §2).
# Works without Terraform: the aws overlay is built from the committed *.example inputs
# when config.env / cluster.env don't exist (CI, fresh clones).
set -euo pipefail

cd "$(dirname "$0")/.."
K8S_VERSION="${K8S_VERSION:-1.35.0}"
SCHEMA_DIR=".cache/kubeconform/v${K8S_VERSION}-standalone-strict"
KINDS="namespace-v1 serviceaccount-v1 role-rbac-v1 rolebinding-rbac-v1 deployment-apps-v1 service-v1 configmap-v1 ingress-networking-v1 networkpolicy-networking-v1"

# Fetch the schemas with curl into a local cache: kubeconform's own Go resolver times out on
# some networks (it ignores the macOS resolver). Kinds not listed here fail as "missing schema".
mkdir -p "$SCHEMA_DIR"
for kind in $KINDS; do
  [ -s "$SCHEMA_DIR/$kind.json" ] && continue
  curl -sfL --retry 3 --max-time 30 -o "$SCHEMA_DIR/$kind.json" \
    "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v${K8S_VERSION}-standalone-strict/$kind.json"
done

validate() {
  echo "== $1" >&2
  kustomize build "$1" | kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
    -schema-location ".cache/kubeconform/{{ .NormalizedKubernetesVersion }}-standalone{{ .StrictSuffix }}/{{ .ResourceKind }}{{ .KindSuffix }}.json"
}

validate k8s/base

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for overlay in k8s/overlays/*/; do
  overlay="${overlay%/}"
  [ -f "$overlay/kustomization.yaml" ] || { echo "== $overlay (no kustomization yet, skipped)" >&2; continue; }
  cp -R k8s "$tmp/"
  for f in "$tmp/$overlay"/*.env.example; do
    [ -e "$f" ] || continue
    [ -f "${f%.example}" ] || cp "$f" "${f%.example}"
  done
  validate "$tmp/$overlay"
  rm -rf "$tmp/k8s"
done
