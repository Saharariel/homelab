#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

source .github/ci/versions.env

die() {
  echo "install-hooks: error: $*" >&2
  exit 1
}

hooks_path="$(git config --get core.hooksPath || true)"
if [ -n "${hooks_path}" ]; then
  die "core.hooksPath is set to '${hooks_path}', so hooks in .git/hooks are ignored.
  Either unset it (git config --unset core.hooksPath) or install these hooks there
  manually."
fi

HOOK_DIR="$(git rev-parse --git-path hooks)"
mkdir -p "${HOOK_DIR}"

if ! command -v gitleaks >/dev/null 2>&1; then
  die "gitleaks is not installed.

  Install it with one of:
    brew install gitleaks
    mise use -g gitleaks@${GITLEAKS_VERSION}
    go install github.com/zricethezav/gitleaks/v8@v${GITLEAKS_VERSION}

  then re-run this script."
fi

installed_version="$(gitleaks version 2>/dev/null | tr -d '[:space:]')"
if [ "${installed_version}" != "${GITLEAKS_VERSION}" ]; then
  echo "install-hooks: warning: gitleaks ${installed_version} installed, CI pins ${GITLEAKS_VERSION}."
  echo "install-hooks:          results may differ slightly from CI."
fi

install_hook() {
  local name="$1" body="$2" path="${HOOK_DIR}/$1"

  if [ -e "${path}" ] && ! grep -q 'homelab-managed-hook' "${path}"; then
    die "${path} already exists and was not installed by this script.
  Move it aside and re-run, or merge the two by hand."
  fi

  printf '%s\n' "${body}" >"${path}"
  chmod +x "${path}"
  echo "install-hooks: installed ${name}"
}

install_hook pre-commit '#!/usr/bin/env bash
# homelab-managed-hook - regenerate with ./scripts/install-hooks.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "pre-commit: gitleaks not installed, refusing to commit." >&2
  echo "pre-commit: run ./scripts/install-hooks.sh, or commit with --no-verify." >&2
  exit 1
fi

gitleaks git "${root}" --staged --config "${root}/.gitleaks.toml" --redact=100 --no-banner'

install_hook pre-push '#!/usr/bin/env bash
# homelab-managed-hook - regenerate with ./scripts/install-hooks.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
exec "${root}/scripts/scan-push-secrets.sh" "$@"'

echo "install-hooks: running an initial full-history scan"
if ! gitleaks git . --config .gitleaks.toml --redact=100 --no-banner; then
  cat >&2 <<'EOF'

install-hooks: the hooks are installed, but the existing history already
contains a finding. Investigate it before pushing anything else - this
repository is public, so a real credential in history must be ROTATED, not
just deleted from the current revision.
EOF
  exit 1
fi

echo
echo "install-hooks: done. pre-commit and pre-push are active and history is clean."
