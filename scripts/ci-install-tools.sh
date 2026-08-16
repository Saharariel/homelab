#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

source .github/ci/versions.env

BIN_DIR="${CI_BIN_DIR:-${HOME}/.local/bin}"
mkdir -p "${BIN_DIR}"

fetch() {
  curl --fail --silent --show-error --location --retry 3 "$@"
}

install_gitleaks() {
  echo "installing gitleaks ${GITLEAKS_VERSION}"
  fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | tar -xz -C "${BIN_DIR}" gitleaks
}

install_kubeconform() {
  echo "installing kubeconform ${KUBECONFORM_VERSION}"
  fetch "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" \
    | tar -xz -C "${BIN_DIR}" kubeconform
}

install_actionlint() {
  echo "installing actionlint ${ACTIONLINT_VERSION}"
  fetch "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C "${BIN_DIR}" actionlint
}

install_flux() {
  echo "installing flux ${FLUX_VERSION}"
  fetch "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C "${BIN_DIR}" flux
}

install_helm() {
  echo "installing helm ${HELM_VERSION}"
  local tmp
  tmp="$(mktemp -d)"
  fetch "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz -C "${tmp}"
  mv "${tmp}/linux-amd64/helm" "${BIN_DIR}/helm"
  rm -rf "${tmp}"
}

for tool in "$@"; do
  case "${tool}" in
    gitleaks) install_gitleaks ;;
    kubeconform) install_kubeconform ;;
    actionlint) install_actionlint ;;
    flux) install_flux ;;
    helm) install_helm ;;
    *) echo "ci-install-tools: unknown tool '${tool}'" >&2; exit 1 ;;
  esac
done

chmod +x "${BIN_DIR}"/* 2>/dev/null || true
echo "${BIN_DIR}" >>"${GITHUB_PATH:-/dev/null}"
