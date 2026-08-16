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

CATALOG="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRDS_CATALOG_REF}"

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
