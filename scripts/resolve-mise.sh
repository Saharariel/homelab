#!/usr/bin/env bash

# Prints the path to the mise binary, or returns 1 if it cannot be found.
#
# Git hooks run non-interactively, so mise is often absent from PATH even when
# 'mise activate' is set up in the user's shell. GUI git clients and IDEs are
# the common case. Fall back to the default install location before giving up.
resolve_mise() {
  if command -v mise >/dev/null 2>&1; then
    command -v mise
  elif [ -x "${HOME}/.local/bin/mise" ]; then
    echo "${HOME}/.local/bin/mise"
  else
    return 1
  fi
}
