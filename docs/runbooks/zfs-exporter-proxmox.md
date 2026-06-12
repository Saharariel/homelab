# zfs_exporter on the Proxmox host

[pdf/zfs_exporter](https://github.com/pdf/zfs_exporter) runs as a systemd unit on the
Proxmox desktop host (`192.168.50.10`, hostname `homelab`) and exposes per-dataset ZFS
metrics on `:9134`. Prometheus scrapes it via the `zfs-proxmox` job
(`apps/base/monitoring/kube-prometheus-stack/values.yaml` -> `additionalScrapeConfigs`),
and Server Hub renders the dataset usage bars from those metrics.

## Install / upgrade

Run on the PVE host (adjust `VER` to the latest release):

```bash
ssh proxmox 'set -e
VER=2.3.12
cd /tmp
curl -sfL -o zfs_exporter.tar.gz "https://github.com/pdf/zfs_exporter/releases/download/v${VER}/zfs_exporter-${VER}.linux-amd64.tar.gz"
curl -sfL -o sha256sums.txt "https://github.com/pdf/zfs_exporter/releases/download/v${VER}/sha256sums.txt"
grep "linux-amd64" sha256sums.txt | sed "s|zfs_exporter-${VER}.linux-amd64.tar.gz|zfs_exporter.tar.gz|" | sha256sum -c -
tar xzf zfs_exporter.tar.gz
install -m 0755 "zfs_exporter-${VER}.linux-amd64/zfs_exporter" /usr/local/bin/zfs_exporter
rm -rf zfs_exporter.tar.gz sha256sums.txt "zfs_exporter-${VER}.linux-amd64"

cat > /etc/systemd/system/zfs_exporter.service << "UNIT"
[Unit]
Description=Prometheus ZFS exporter
After=network-online.target zfs.target

[Service]
ExecStart=/usr/local/bin/zfs_exporter --web.listen-address=:9134
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now zfs_exporter
sleep 1
curl -s localhost:9134/metrics | grep -m4 "^zfs_dataset"'
```

The final `curl` must print `zfs_dataset_used_bytes{...name="tank/..."}` /
`zfs_dataset_available_bytes{...}` lines. Server Hub's Prometheus adapter
(`server-hub:src/server_hub/adapters/prometheus.py`) queries exactly those two metric
names joined on the `name` label -- if the names differ, update the `_ZFS_*` constants
there.

## Verify the scrape

After Flux applies the values change:

1. `kubectl get --raw "/api/v1/namespaces/monitoring/services/prometheus-prometheus:9090/proxy/api/v1/targets" | grep zfs-proxmox` -- target should be `"health":"up"`.
2. The "ZFS datasets" bars appear on the Server Hub dashboard monitoring panel.

## Notes

- The exporter needs the `zfs` CLI, so it runs as root on the PVE host (read-only
  commands only).
- Port 9134 is LAN-only; nothing exposes it beyond the home network.
- This is host-level state outside the GitOps loop -- it must be reinstalled after a
  Proxmox rebuild (add it to the rebuild checklist).
