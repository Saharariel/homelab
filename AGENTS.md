# Sahar's Personal GitOps Homelab

GitOps repo for a K3s homelab running various production services including jellyfin, arr stack and more.  

  
Flux reconciles `main` onto the cluster, so a merged PR is a deploy.  
The repo is public!! keep real domains, IPs and secret values out of it,  
they arrive via ExternalSecrets.

## Layout

- `clusters/production/` - the three Flux roots, applied in order  
`controllers` -> `infra` -> `apps`. `controllers` and `apps` substitute `${BASE_DOMAIN}`, `${BASE_PATH}`, `${NFS_*}` from the `cluster-params` and `base-path` Secrets.  

- `{apps,controllers}/base/<group>/<app>/` holds the manifests; `{apps,controllers}/production/...` is a thin overlay that sets the namespace and points at the base.  
To disable an app, comment out its overlay `resources` (see `apps/production/longhorn`).  

- `infrastructure/production/` - namespaces, cluster-wide ExternalSecrets, the substitution Secrets, k3s patches.  

- `docs/runbooks/` and `docs/homelab-*.md` are gitignored and local-only.

## Conventions

- **Secrets**: an `ExternalSecret` against `ClusterSecretStore/aws-parameter-store` (AWS SSM).  
A committed `kind: Secret` is either SOPS-encrypted (`clusters/production/.sops.yaml`) or annotated `homelab.dev/plaintext-reason`. perfer externalsecret over sops-encrypted.  

- **App state**: config/DB lives on a static `local` PV + PVC named `<app>-config` at `/var/lib/appconfig/<app>`, node-pinned to `worker-node-1`, with a `Recreate` Deployment strategy. SQLite on NFS locks up, so config stays on local SSD. Media mounts the shared `media-data` PVC (proxmox zfs pool).  

- **Ingress**: Traefik `websecure`, host `<app>.homelab`, TLS from cert-manager `ca-issuer`.  
Copy an existing app (e.g. `apps/base/media/prowlarr`).  

- **Helm**: every `HelmRepository` sets `metadata.namespace` explicitly, since Renovate reads raw files without rendering kustomize. Charts and images are pinned; Renovate opens the bump PRs.  

- **Commits**: Conventional Commits, `type(scope): summary`, e.g. `fix(monitoring): ...`.

## Validate

Tools are pinned in `mise.toml`.  
  
Run `mise run ci` before pushing: gitleaks, lint, kustomize build, Flux render with the `.github/ci/*.yaml` fixtures, kubeconform, and a render of every HelmRelease.  
  
Git hooks in `.githooks/` run the secret scans.

## Cluster gotchas

- Flux reverts manual `kubectl` edits and scales within ~10 min. For hands-on migrations, `flux suspend kustomization apps` first and resume after.  

- The worker is RAM-starved (soft-lockup reboots under pressure): give new workloads honest memory requests and keep heavy ones off it. Its GPU is an Intel iGPU (QuickSync), with no CUDA.  

- A Helm upgrade failing on an immutable StatefulSet field: `kubectl delete sts <name> --cascade=orphan`, then `flux reconcile hr <name> --force`.
