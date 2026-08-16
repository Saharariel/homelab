# Contributing

## Required bootstrap

Run this once per clone, before you commit anything:

```bash
./scripts/install-hooks.sh
```

Git does not activate a repository's hooks on clone, so a fresh clone has no
secret scanning until you run this. The script installs a `pre-commit` hook
(scans staged content) and a `pre-push` hook (scans every commit the push would
publish), then verifies the existing history is clean.

It requires [gitleaks](https://github.com/gitleaks/gitleaks) at the version
pinned in `.github/ci/versions.env`:

```bash
brew install gitleaks
```

## How secrets are kept out

This repository is public. Four independent layers guard it, because any single
one can be bypassed:

| Layer | Catches | Bypassable by |
| --- | --- | --- |
| `pre-commit` hook | staged secrets | `--no-verify`, not installed |
| `pre-push` hook | secrets anywhere in the outgoing commits | `--no-verify`, not installed |
| GitHub push protection | known credential patterns, server side | repository admin |
| CI `secrets` job | same scan, independently, as a merge gate | nothing, if the check is required |

The local hooks are a convenience for honest mistakes. The CI job is the
enforcement point, so make `ci / secret scan` a required status check.

A local hook cannot make a hard guarantee: CI runs *after* GitHub has already
accepted the push. **If a real credential ever reaches the remote, rotate it.**
Deleting it from the latest revision is not enough, because the object remains
reachable in the public history.

## Secrets in manifests

Every `kind: Secret` must be SOPS-encrypted:

```bash
sops --encrypt --in-place path/to/secret.yaml
```

If a Secret genuinely holds no secret values, annotate it instead of encrypting
it, and say why:

```yaml
metadata:
  annotations:
    homelab.dev/plaintext-reason: LAN paths only, already public in README.md
```

`scripts/validate-manifests.py` enforces this per YAML document, so a plaintext
Secret cannot ride along beside an encrypted one.

## Running CI locally

Every CI step is a script you can run yourself:

```bash
./scripts/build-kustomizations.sh                      # every kustomization builds
./scripts/flux-build.sh build                          # all three Flux roots render
./scripts/kubeconform.sh build/*.yaml                  # manifests match the k8s API
./scripts/render-helmreleases.py build/*.yaml --out build/helm
./scripts/validate-manifests.py                        # YAML hygiene + Secret policy
```

`scripts/ci-install-tools.sh flux helm kubeconform gitleaks actionlint`
installs the pinned versions into `~/.local/bin`.

## Tool and CI fixtures

`.github/ci/versions.env` is the single source of truth for tool versions, used
by both CI and the local hooks so they cannot disagree. Renovate updates it.

`.github/ci/*.yaml` are Flux Kustomizations used only for rendering in CI. They
substitute fake values (`example.invalid`, `192.0.2.10`, `/ci/...`) because
`flux build --dry-run` cannot read the cluster's Secrets. Never put real
cluster values or a kubeconfig in them.

When a manifest starts using a new `${VARIABLE}`, add it to all three files
under `spec.postBuild.substitute`, or CI will fail with an unresolved
substitution.
