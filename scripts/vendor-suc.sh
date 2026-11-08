#!/bin/sh
# Vendor the system-upgrade-controller release manifests for one version.
#
# Flux builds every 10 minutes; pulling these from GitHub release URLs at build
# time took the whole controllers Kustomization down whenever GitHub's release
# downloads failed. Renovate runs this as a post-upgrade task when it bumps the
# version, so the files and the version always move together.
#
# Usage: scripts/vendor-suc.sh v0.21.0
set -eu

version=${1:?usage: $0 vX.Y.Z}
case $version in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "not a release version: $version" >&2; exit 1 ;;
esac

dir=$(dirname "$0")/../controllers/base/system-upgrade-controller
base=https://github.com/rancher/system-upgrade-controller/releases/download/$version

for asset in crd.yaml system-upgrade-controller.yaml; do
  curl -fsSL --retry 3 -o "$dir/$asset.tmp" "$base/$asset"
  mv "$dir/$asset.tmp" "$dir/$asset"
done
sed -i "s#releases/download/v[0-9][0-9.]*/#releases/download/$version/#" "$dir/kustomization.yaml"
