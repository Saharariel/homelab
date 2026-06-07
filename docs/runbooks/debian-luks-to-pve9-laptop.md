# Laptop → encrypted Proxmox VE 9 (Debian 13 + LUKS), then join the cluster

Turns the Dell laptop (currently bare-metal Ubuntu k3s control plane,
`saharlinux` @ `192.168.50.19`) into an **encrypted Proxmox VE 9** node that
hosts the control-plane VM. The PVE ISO can't encrypt root, so we install
**Debian 13 with guided LUKS** and put Proxmox on top (Proxmox's own supported
method). End state is byte-for-byte a normal PVE node, just on an encrypted root.

> **Why encrypt this node:** it holds etcd + every Kubernetes Secret at rest.
> LUKS protects them if the laptop is stolen.
>
> **Safety:** this only touches the laptop's **NVMe SSD (`nvme0n1`)**. The
> desktop and its `tank` pool are untouched. The laptop's own 931 G HDD (`sda`)
> is left alone. Nothing here runs against the desktop.

---

## 0. Before you start (this destroys the old control plane)
This *is* part of the cutover — reinstalling the laptop kills the live k3s
control plane. That's fine: cluster state lives in **git + Parameter Store +
`tank`**, and the worker keeps serving during the gap (see REBUILD-TODO §0/§5).
- [ ] Confirm the `deployment/REBUILD-TODO.md` prep items are done (secrets in Parameter Store, pihole backed up, `tank` intact).
- [ ] Download the **Debian 13 (Trixie) netinst** ISO, flash to USB.
- [ ] Decide IPs: the **laptop PVE host** needs its *own* IP, **not** `.19` —
      `.19` is the *master VM*. Use e.g. **`192.168.50.11/24`** for the host.
- [ ] BIOS: UEFI mode, enable the **TPM** (optional, for future use), note boot order.

## 1. Install Debian 13 with an encrypted root
1. Boot the Debian installer → standard install.
2. Hostname e.g. `pve-laptop`; set a root password + a regular user.
3. **Partitioning → "Guided – use entire disk and set up encrypted LVM".**
   - **Select `nvme0n1` (238 G SSD) ONLY.** Do **not** select `sda` (the 931 G HDD).
   - Set a strong **LUKS passphrase** → save it to your password manager.
4. Software selection: **uncheck desktop environment**; keep **SSH server** + standard utils.
5. Finish, reboot, remove USB. At boot you'll be prompted for the LUKS passphrase (we make that remote in §4).

## 2. Network: static IP + a bridge for the VMs
Proxmox needs a `vmbr0` bridge. Edit `/etc/network/interfaces` (replace `enpXsY` with your NIC from `ip a`):
```
auto lo
iface lo inet loopback

iface enpXsY inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.50.11/24
    gateway 192.168.50.1
    bridge-ports enpXsY
    bridge-stp off
    bridge-fd 0
```
Fix `/etc/hosts` so the hostname resolves to the **real** IP (the gotcha that failed `pve8to9`):
```
127.0.0.1 localhost
192.168.50.11 pve-laptop.local pve-laptop
```
`systemctl restart networking` (or reboot).

## 3. Install Proxmox VE 9 on top
> Verify the repo + key against the wiki on the day (the key filename changes): https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
```bash
# repo
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-install-repo.list
# signing key (confirm current URL on the wiki)
wget https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
  -O /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg

apt update && apt full-upgrade -y
apt install -y proxmox-default-kernel
reboot                       # boot the Proxmox kernel

# after reboot:
apt install -y proxmox-ve postfix open-iscsi chrony
apt remove -y linux-image-amd64 'linux-image-6.12*'   # drop the Debian kernel
apt remove -y os-prober
update-grub
reboot
```
Web UI now at `https://192.168.50.11:8006`. Storage `local` + `local-lvm` (the SSD) exist by default → that's where the master VM lands.

## 4. Remote LUKS unlock (dropbear-initramfs)
So you don't need a monitor to type the passphrase on every boot:
```bash
apt install -y dropbear-initramfs
# allow your laptop/admin key to unlock at early boot:
mkdir -p /etc/dropbear/initramfs
cp ~/.ssh/authorized_keys /etc/dropbear/initramfs/authorized_keys   # or paste your pubkey
# give initramfs a static IP (so you can reach it before the OS is up):
echo 'IP=192.168.50.11::192.168.50.1:255.255.255.0:pve-laptop:vmbr0:off' >> /etc/initramfs-tools/initramfs.conf
update-initramfs -u
```
On boot, unlock remotely:
```bash
ssh -p 22 root@192.168.50.11      # lands in initramfs (separate host key — expect a known_hosts warning)
cryptroot-unlock                  # type the LUKS passphrase → boot continues
```
*(Alternative: TPM2 auto-unlock via `systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes` — convenient but add the PIN so a stolen, powered-on laptop can't self-unlock. dropbear keeps full passphrase strength and is the pick for a headless control plane.)*
Being a laptop, the **battery rides through brief power cuts**, so unattended unlock matters less than on the desktop.

## 5. Form the cluster + set two_node
On the **desktop** (`homelab`, already PVE 9), create the cluster if not already:
```bash
pvecm create homelab-cluster
```
On the **laptop**, join it:
```bash
pvecm add 192.168.50.10           # the desktop's IP; enter root@desktop password
```
Then, because there's no qdevice yet, edit `/etc/pve/corosync.conf` on **either** node
(it syncs), bump `config_version`, and add `two_node: 1` to the quorum block:
```
quorum {
  provider: corosync_votequorum
  two_node: 1
}
```
Save → corosync reloads. Now a single node up still has quorum (read-write pmxcfs).
**Remove `two_node: 1` when you add the RPi qdevice later.**

## 6. Verify + ready for Terraform
- [ ] `pvecm status` → both nodes, Quorate.
- [ ] `https://192.168.50.11:8006` reachable; `local-lvm` present.
- [ ] Create the Terraform API token: `pveum user token add terraform@pve iac ...`.
- [ ] `terraform.tfvars`: `pve_node_master = "pve-laptop"`, `datastore_master = "local-lvm"`.
- [ ] Back up the LUKS header: `cryptsetup luksHeaderBackup /dev/nvme0n1p3 --header-backup-file laptop-luks-header.img` → store off-box. **Passphrase + header backup = your recovery; losing both = losing the disk.**
