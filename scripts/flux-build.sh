#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

OUT_DIR="${1:-build}"
CI_DIR=".github/ci"

declare -A ROOTS=(
  [controllers]=./controllers/production
  [infra]=./infrastructure/production
  [apps]=./apps/production
)

command -v flux >/dev/null 2>&1 || {
  echo "flux-build: flux CLI not found" >&2
  exit 1
}

mkdir -p "${OUT_DIR}"
failed=0

for name in controllers infra apps; do
  path="${ROOTS[$name]}"
  kustomization="${CI_DIR}/${name}.yaml"
  out="${OUT_DIR}/${name}.yaml"

  echo "flux-build: rendering ${name} (${path})"

  if ! flux build kustomization "${name}" \
      --path "${path}" \
      --kustomization-file "${kustomization}" \
      --dry-run \
      --strict-substitute \
      >"${out}"; then
    echo "::error file=${kustomization}::${name} failed to render" >&2
    failed=1
    continue
  fi

  if leftovers="$(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*(:[^}]*)?\}' "${out}")"; then
    echo "::error file=${kustomization}::${name} has unresolved substitutions:" >&2
    echo "${leftovers}" | head -20 >&2
    echo "  Add the variable to ${kustomization} under spec.postBuild.substitute," >&2
    echo "  using a non-secret fixture value." >&2
    failed=1
    continue
  fi

  echo "flux-build: ${name} OK ($(grep -c '^---' "${out}") documents)"
done

exit "${failed}"
