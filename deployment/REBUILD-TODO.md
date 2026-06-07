# Cluster rebuild — cutover checklist

> **Merging PR #214 = the cutover.** It encodes the *rebuilt* cluster's desired
> state (Cilium KPR, no SOPS, bootstrap-injected secrets, NFS-only storage).
> Applying it to the running cluster is **not** a no-op — so the plan is:
> **prepare → delete the VMs → rebuild from zero → verify.**
>
> The data is safe the whole time: everything stateful lives on the desktop's
> ZFS pool (`tank/k3s-pvcs`, `tank/data`, `tank/photos`) and is served over NFS.
> The VMs are cattle. **Nothing in this process should ever touch `tank`.**

---

## 0. Why this can't be a normal merge (context)
On merge, Flux against the *old* cluster would:
- Flip **live** Cilium to `kubeProxyReplacement: true` while k3s still runs kube-proxy → the wedge that failed 3×.
- Reference `${K3S_APISERVER_HOST/PORT/POD_CIDR}` that don't exist in the live `cluster-params` → substitution error.
- Prune the now-deleted SOPS `aws-eso-credentials` + `cluster-params` → ESO breaks.

→ So we merge **only when we're ready to delete the VMs and rebuild.**

---

## 1. Decisions to lock first (everything else depends on these)
- [x] **D1 — DECIDED:**
  - **Desktop** = in-place `pve8to9`, **no LUKS** (unencrypted root). Finish the pre-flight + `apt dist-upgrade`.
  - **Laptop** = fresh **Debian 13 + LUKS → PVE 9** (encrypted root — it holds etcd/secrets). Unlock via **dropbear-initramfs** (remote SSH unlock, headless-friendly; battery rides through brief power loss). Runbook: `docs/runbooks/debian-luks-to-pve9-laptop.md`.
- [x] **D2 — DECIDED: cluster (shared UI), no qdevice yet → RPi later, and SET `two_node: 1`.** A 2-node cluster with no qdevice loses quorum if either node is down → survivor's `pmxcfs` goes read-only (running VMs keep running, but no start/stop/edit). `two_node: 1` in `/etc/pve/corosync.conf` is the stopgap until the qdevice is added.
- [x] **D3 — constrained by D1 = no-LUKS:** keyfile-on-encrypted-root is off the table → choose **passphrase** (manual each boot) or **USB keyfile** for `tank/k3s-pvcs`. Still a separate manual `send|recv`; non-blocking for the rebuild.
- [x] **D4 — CA continuity:** ✅ **PERSIST.** `homelab-ca-tls` stored in Parameter Store (`/homelab/cert-manager/HOMELAB_CA_TLS_{CRT,KEY}`, SecureString); cert-manager no longer generates the CA — ESO materialises it (`controllers/base/cert-manager/ca-externalsecret.yaml`). Rebuild reuses the same root → devices stay trusted.
- [ ] **D5 — Cilium datapath:** `upstream` (stock eBPF KPR) vs `safe` (legacy host routing). Plan: try `upstream` on the throwaway VM, keep the validation gate, fall back to `safe` if it wedges.
- [x] **D6 — DECIDED: VM disks on `local-lvm` (host NVMe SSD), unencrypted** for fast OS (cattle). Verified: desktop `nvme0n1` 238 G → `local-lvm`; laptop `nvme0n1` 238 G → becomes `local-lvm` after the fresh PVE install (it also has a 931 G HDD left free). Terraform wired.

---

## 2. Code gaps to fix in the PR before merge
- [ ] **C1 — Terraform: add `machine = q35` to the worker VM** (+ likely OVMF/UEFI). `hostpci { pcie = true }` is invalid on the default i440fx → **GPU passthrough won't attach**.
- [~] **C2 — PVE-host storage ALREADY EXISTS** (verified live): pool `tank` ONLINE, datasets `data`/`k3s-pvcs`/`photos`/`proxmox`, and `/etc/exports` for all three → `192.168.50.0/24`. **Do NOT automate provisioning** — data is irreplaceable; never `zpool create`/`zfs create`/`zfs destroy` in a role. Recovery after a desktop reinstall is only `zpool import tank` (non-destructive — attaches the existing pool) + restore `/etc/exports`. Capture as a **descriptive runbook** (`docs/runbooks/pve-host-storage.md`), not a role. The ONE missing piece is the **encrypted `tank/k3s-pvcs` dataset (currently encryption=off)** → that's **D3**, a manual gated `send|recv`, never automated.
- [ ] **C3 — (optional) Cilium role toggle** `upstream | safe` per D5; keep the Ready/PV-mount validation gate.
- [x] **C4 — bumped** to k3s `v1.36.1` + Cilium `1.19.4` (group_vars/all.yml). ⚠️ Confirm those tags exist, and note **newer Cilium 1.19 may behave differently on the D5 datapath test** — verify on the throwaway VM (the RCA was on an older Cilium).
- [ ] **C5 — Verify substitution vars match.** Every `${VAR}` in the manifests must be supplied by a bootstrap-injected secret: `cluster-params` (BASE_DOMAIN, K3S_APISERVER_HOST, K3S_APISERVER_PORT, POD_CIDR) + `base-path` (BASE_PATH, NFS_SERVER, NFS_ROOT). No missing keys.

---

## 3. Prepare / back up BEFORE merge
- [ ] **Back up pihole LXC (DNS) — it is NOT in the IaC:** `ssh proxmox 'vzdump 105 --dumpdir /tank/backups --compress zstd'` (lands on tank → survives the reinstall).
- [ ] **Confirm every app secret is in AWS Parameter Store under `/homelab/*`** — the fresh cluster pulls *everything* from there via ESO. Spot-check each `ExternalSecret`'s `remoteRef` keys exist.
- [ ] **authentik PG superuser pw** already pinned in Parameter Store — verify it still matches.
- [x] **CA persisted:** `homelab-ca-tls` (cert + key) is in Parameter Store (done).
- [ ] **Confirm `tank` data is intact + exported:** `tank/k3s-pvcs` (18 PV dirs), `tank/data`, `tank/photos`. The rebuilt cluster binds static PVs to these existing dirs.
- [ ] **Create the rebuild secrets** — ansible-vault'd `deployment/ansible/group_vars/secrets.yml`: `k3s_token`, `eso_aws_access_key_id`, `eso_aws_secret_access_key`, `base_domain`. Store the vault passphrase in your password manager.
- [ ] **SSH keypair for the VMs:** public key → `terraform.tfvars` (`ssh_public_keys`); private key → the mgmt runner + password manager.
- [ ] **Populate `deployment/terraform/terraform.tfvars`:** endpoint, API token, node names (`pvecm nodes`), datastores (D6), `worker_igpu_pci_id = 0000:00:02.0`, ssh keys.
- [ ] **Record current state for parity check:** app list, ingress hostnames, GPU pci id, node IPs (.18 worker / .19 master).

---

## 4. Infrastructure groundwork (per the decisions)
- [ ] **G1 — Desktop → PVE 9** (in-place finish OR encrypted reinstall, per D1). Pre-flight `pve8to9 --full` must be `FAILURES: 0`.
- [ ] **G2 — Laptop → reinstall** Debian 13 + LUKS → PVE 9 (encrypted root). Back up nothing on it (it's the old bare-metal control plane; state is in git + Parameter Store + tank).
- [ ] **G3 — (if D2 = cluster) form the 2-node cluster + qdevice.** Decide the qdevice host (Pi / the mgmt LXC / pihole LXC).
- [ ] **G4 — Proxmox API token** `terraform@pve!iac` (+ a role with VM.*, Datastore.*, SDN/network as needed).
- [ ] **G5 — iGPU VFIO bound on the desktop** (confirm `0000:00:02.0` → vfio-pci after any reinstall).
- [ ] **G6 — Mgmt/Semaphore LXC:** terraform + ansible + kubectl/flux installed; holds TF state, the SSH private key, the vault passphrase, the API token.
- [ ] **G7 — Encrypted VM-disk datastore exists** on each node (per D6).
- [ ] **G8 — NFS export live** on the desktop for `tank/k3s-pvcs` (per C2).

---

## 5. Cutover sequence (rebuild day)
1. [ ] Final backups confirmed (pihole, secrets in Parameter Store, `tank` intact).
2. [ ] **Merge PR #214 to `main`.**
3. [ ] **Delete the old VMs:** `qm stop 103 && qm destroy 103` (old worker) on the desktop; the old laptop control plane is destroyed by its reinstall.
4. [ ] `cd deployment/terraform && terraform init && terraform apply` → new master (.19) + worker (.18).
5. [ ] `terraform output -raw ansible_inventory > ../ansible/inventory.yml`
6. [ ] `cd ../ansible && ansible-playbook -i inventory.yml site.yml --ask-vault-pass`
7. [ ] Watch the gates: node **Ready** (Cilium), a **PV-mounting pod starts** (NFS/masquerade OK), Flux reconciles, ESO syncs.
8. [ ] Copy `/tmp/k3s-kubeconfig` → `~/.kube/config`.

---

## 6. Post-rebuild verification
- [ ] All nodes `Ready`; all `flux get kustomizations` = `True`.
- [ ] All `ExternalSecrets` = `SecretSynced`.
- [ ] All PVCs `Bound` to the static NFS PVs — **data intact** (check a DB row count / app login).
- [ ] Ingress + TLS works (re-import the CA on devices if D4 = regenerate).
- [ ] Jellyfin GPU transcode works (`gpu.intel.com/i915` advertised on the worker).
- [ ] Atomic moves intact (radarr hardlink test → same inode).
- [ ] pihole restored + DNS resolving.
- [ ] authentik / vaultwarden / immich / n8n / moneyman / *arr stack all up.

---

## 7. Rollback / safety
- `tank` is never touched → worst case is fix-forward (re-run ansible) not data loss.
- Keep a copy of the old laptop's `/var/lib/rancher/k3s` (datastore + token + CA) until the rebuild is verified — lets you *restore the same control plane* instead of rebuilding if needed.
- Static PVs bind to **existing** `tank/k3s-pvcs/<name>` dirs — never `kubectl delete pv` with a Delete reclaim policy during this.
