#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG="${REPO_ROOT}/.gitleaks.toml"
ZERO_SHA='0000000000000000000000000000000000000000'

die() {
  echo "pre-push: $*" >&2
  exit 1
}

remote_name="${1:-origin}"

require_scanner() {
  if ! command -v gitleaks >/dev/null 2>&1; then
    die "gitleaks is not installed, refusing to push.
  Install it and re-run scripts/install-hooks.sh, or bypass once with
  'git push --no-verify' if you are certain this push carries no secrets."
  fi

  [ -f "${CONFIG}" ] || die "missing ${CONFIG}, refusing to push."
}

scan() {
  local label="$1" log_opts="$2"
  require_scanner
  echo "pre-push: scanning ${label}"
  if ! gitleaks git "${REPO_ROOT}" \
      --config "${CONFIG}" \
      --log-opts "${log_opts}" \
      --redact=100 \
      --no-banner; then
    cat >&2 <<EOF

pre-push: BLOCKED - gitleaks found a potential secret in the commits above.

The finding is in committed history, so deleting the line from your working
tree is not enough. Rewrite the offending commits (git rebase -i / filter-repo),
or if this is a false positive add an allowlist entry to .gitleaks.toml.

If the value is real and has ever been pushed, rotate it. This repository is
public.
EOF
    exit 1
  fi
}

found_ref=0
while read -r local_ref local_sha remote_ref remote_sha; do
  if [ "${local_sha}" = "${ZERO_SHA}" ]; then
    continue
  fi

  found_ref=1

  if [ "${remote_sha}" = "${ZERO_SHA}" ]; then
    scan "new ref ${local_ref} (commits not yet on ${remote_name})" \
      "${local_sha} --not --remotes=${remote_name}"
  else
    if [ "${local_sha}" = "${remote_sha}" ]; then
      continue
    fi
    scan "${remote_ref} (${remote_sha:0:8}..${local_sha:0:8})" \
      "${remote_sha}..${local_sha}"
  fi
done

if [ "${found_ref}" -eq 0 ]; then
  echo "pre-push: nothing to scan"
fi

echo "pre-push: no secrets detected"
