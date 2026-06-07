# deployment/ — cattle rebuild of the k3s cluster (Terraform + Ansible)

On-demand, operator-run provisioning of the whole cluster from scratch. **Not**
git-triggered — you run it deliberately when you want a fresh deployment.

## Target architecture
- **2-node Proxmox cluster** (+ a corosync-qdevice tiebreaker to avoid 2-node quorum lockup).
  - `pve-laptop` — the reinstalled Dell, **encrypted ZFS**. Hosts **master-01** (control plane).
  - `pve-desktop` — the i7 with the `tank` ZFS mirror + Intel iGPU. Hosts **worker-01** (QSV passthrough).
- **k3s** with `--disable-kube-proxy --flannel-backend=none --disable-network-policy --secrets-encryption`.
- **Cilium** as kube-proxy replacement — **SAFE config only** (see below).
- **Flux** bootstraps from this repo (`clusters/production`); **ESO** pulls app secrets from the external backend.
- All app state on **static NFS PVs** (`tank/k3s-pvcs`); nothing stateful on the VMs → VMs are cattle.

## Run it (from your management LXC)
```bash
cd deployment/terraform
terraform init && terraform apply              # creates the VMs (secrets via TF_VAR_*/tfvars)
terraform output -raw ansible_inventory > ../ansible/inventory.yml

cd ../ansible
ansible-playbook -i inventory.yml site.yml --ask-vault-pass
```
`site.yml` order: base OS → k3s control plane → **Cilium (validated)** → workers → Flux + bootstrap secrets.

## ⚠️ Cilium KPR — the one thing not to "fix" to the docs' defaults
KPR with **eBPF host routing** (Cilium's default) breaks the k3s loopback apiserver
path → NotReady → NFS wedge. Three guard-rails in `roles/cilium/templates/cilium-values.yaml.j2`
prevent it: `bpf.hostLegacyRouting: true`, `bpf.masquerade: false`, `socketLB.hostNamespaceOnly: true`
(+ tunnel/vxlan). The role **asserts `Host Routing: Legacy` and aborts** if it ever comes up in eBPF
mode. Full context: `docs/runbooks/cilium-kpr-rca-2026-05-30.md`.

## Security model (see the threat plan we wrote)
- **Disk at rest**: VM disks on **encrypted ZFS datastores** (`datastore_master/worker`); the desktop's
  `tank/k3s-pvcs` is a ZFS-encrypted dataset. Keys unlocked at PVE host boot.
- **Secrets at rest in-cluster**: k3s `--secrets-encryption` (asserted by `k3s_server`).
- **Bootstrap secrets**: the ESO backend credential and cluster substitution secrets are injected by
  `flux_bootstrap` from an **ansible-vault'd** `group_vars/secrets.yml` (vault passphrase from your
  password manager). App secrets flow from the backend through ESO.
- **ESO identity**: least-privilege, read-only, scoped to `/homelab/*`.

## Prerequisites (manual, before first run)
1. Both nodes installed as Proxmox with **encrypted ZFS**, joined into a cluster (+qdevice).
2. A Proxmox **API token** for Terraform (`terraform@pve!iac`).
3. iGPU bound for passthrough on `pve-desktop` (VFIO); note its PCI id → `worker_igpu_pci_id`.
4. `terraform.tfvars` (from `.example`) and `ansible/group_vars/secrets.yml` (ansible-vault) populated.

## Files
```
terraform/  versions, providers, variables, vms (master+worker, cloud-init, GPU), outputs (renders inventory)
ansible/    site.yml + roles: common, k3s_server, k3s_agent, cilium, flux_bootstrap
```
