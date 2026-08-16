#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

source .github/ci/versions.env

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/kubeconform.sh <rendered-manifest> [...]" >&2
  exit 2
fi

CATALOG="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRDS_CATALOG_REF}"

SKIP_KINDS="${KUBECONFORM_SKIP:-}"

args=(
  -strict
  -summary
  -kubernetes-version "${KUBERNETES_VERSION}"
  -schema-location default
  -schema-location "${CATALOG}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
)

if [ -n "${SKIP_KINDS}" ]; then
  args+=(-skip "${SKIP_KINDS}")
fi

exec kubeconform "${args[@]}" "$@"
