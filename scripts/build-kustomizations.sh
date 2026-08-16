#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

failed=0
total=0
passed=0

while IFS= read -r file; do
  dir="$(dirname "${file}")"
  total=$((total + 1))

  if output="$(kubectl kustomize "${dir}" 2>&1 >/dev/null)"; then
    passed=$((passed + 1))
  else
    echo "::error file=${file}::kustomize build failed" >&2
    echo "    ${output//$'\n'/$'\n'    }" >&2
    failed=1
  fi
done < <(git ls-files '*kustomization.yaml' | sort -u)

echo "build-kustomizations: ${passed}/${total} kustomizations built"
exit "${failed}"
