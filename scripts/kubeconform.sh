#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/kubeconform.sh <rendered-manifest> [...]" >&2
  exit 2
fi

if [ -z "${KUBERNETES_VERSION:-}" ] || [ -z "${CRDS_CATALOG_REF:-}" ]; then
  echo "kubeconform: KUBERNETES_VERSION and CRDS_CATALOG_REF must be set." >&2
  echo "kubeconform: they come from [env] in mise.toml - run via 'mise exec --' or activate mise." >&2
  exit 1
fi

# Catalog 63669a5 corrupts the CRD provider whitelist's field named "properties"
# in ClusterSecretStore v1: a boolean is placed inside the schema's properties
# map, which fails the Draft 4 metaschema. Pin only this GVK to its last known
# good schema; all other schemas still use the Renovate-managed catalog ref.
ESO_STORE_SCHEMA_REF="fd90051867733c60d32d16450556e9cd18459aef"
# Catalog 27233a5 uses \\u escapes in CiliumNetworkPolicy v2 log.value patterns,
# which kubeconform's Go regexp compiler rejects. Keep this exact GVK on the
# prior compiling schema until the upstream pattern is Go-compatible again.
CILIUM_POLICY_SCHEMA_REF="3eb90d47aba8d61919d4419dd38301536e32a94b"
CATALOG="https://raw.githubusercontent.com/datreeio/CRDs-catalog"
CATALOG+='/{{if and (eq .Group "external-secrets.io") (eq .ResourceKind "clustersecretstore") (eq .ResourceAPIVersion "v1")}}'
CATALOG+="${ESO_STORE_SCHEMA_REF}"
CATALOG+='{{else if and (eq .Group "cilium.io") (eq .ResourceKind "ciliumnetworkpolicy") (eq .ResourceAPIVersion "v2")}}'
CATALOG+="${CILIUM_POLICY_SCHEMA_REF}{{else}}${CRDS_CATALOG_REF}{{end}}"

args=(
  -strict
  -summary
  -kubernetes-version "${KUBERNETES_VERSION}"
  -schema-location default
  -schema-location "${CATALOG}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
)

if [ -n "${KUBECONFORM_SKIP:-}" ]; then
  args+=(-skip "${KUBECONFORM_SKIP}")
fi

exec kubeconform "${args[@]}" "$@"
