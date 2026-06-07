# deployment/ — k3s cluster provisioning (Terraform + Ansible)

On-demand, operator-run provisioning of the cluster from scratch. Not
git-triggered — run it deliberately for a fresh deployment.

## Architecture
- **2-node Proxmox cluster** hosting two VMs: a control-plane (`master-01`) and a
  worker (`worker-01`, with iGPU passthrough for transcoding).
- **k3s** with `--disable-kube-proxy --flannel-backend=none --disable-network-policy --secrets-encryption`.
- **Cilium** as the CNI and kube-proxy replacement.
- **Flux** reconciles this repo (`clusters/production`); **ESO** pulls app secrets from the external backend.
- All application state lives on **static NFS PVs**; the VMs hold no state.

## Run it
```bash
cd deployment/terraform
terraform init && terraform apply
terraform output -raw ansible_inventory > ../ansible/inventory.yml

cd ../ansible
ansible-playbook -i inventory.yml site.yml --ask-vault-pass
```
Play order: base OS → k3s control plane → Cilium → workers → Flux.

## Security
- k3s `--secrets-encryption` encrypts Secrets at rest in the datastore.
- The control-plane node runs on a LUKS-encrypted root.
- Bootstrap secrets (the ESO backend credential + Flux substitution params) are
  injected by `flux_bootstrap` from an ansible-vault'd `group_vars/secrets.yml`;
  app secrets flow from the backend through ESO with a read-only, scoped identity.

## Prerequisites
1. Both nodes installed as Proxmox 9 and joined into a cluster.
2. A Proxmox API token for Terraform.
3. iGPU bound for VFIO passthrough on the worker node; note its PCI id.
4. `terraform.tfvars` and `ansible/group_vars/secrets.yml` (ansible-vault) populated.

## Layout
```
terraform/  providers, variables, vms, outputs
ansible/    site.yml + roles: common, k3s_server, k3s_agent, cilium, flux_bootstrap
```
