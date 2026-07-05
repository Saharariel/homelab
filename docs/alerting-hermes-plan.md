# Homelab Alerting and Hermes Triage Plan

This plan turns the existing kube-prometheus-stack into the source of truth for homelab health, then lets Hermes consume alerts and produce investigation plans/direct notifications.

## Goals

- Alert on core infrastructure, Kubernetes control plane/node health, GitOps, secrets, certificates, storage, DNS, ingress, public endpoints, and important apps.
- Keep alert rules and probes in GitOps so changes are reviewable.
- Route urgent events to the user directly while giving Hermes enough labels/runbook context to investigate.
- Start with read-only triage. Any write/restart/GitOps remediation should require explicit approval.

## Current baseline

Existing components already deployed:

- kube-prometheus-stack: Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter
- blackbox-exporter
- Discord receiver for Alertmanager
- Flux Discord notification provider
- Proxmox ZFS exporter at `192.168.50.10:9134`

Observed gaps before this change:

- Blackbox covered only a few internal services.
- No synthetic checks for LAN ingress, public Cloudflare endpoints, Pi-hole DNS, Proxmox API/NFS, or kubelet/API TCP reachability.
- Flux, cert-manager, and external-secrets metrics were not explicitly selected for Prometheus scraping.
- No homelab-specific alert labels/runbook hints for Hermes triage.
- Hermes did not yet have a stable alert ingestion path.

## What this PR adds

### Synthetic probes

`apps/base/monitoring/blackbox-exporter/probes.yaml` now defines probe groups:

| Probe group | Signal | Examples |
|---|---|---|
| `internal` | Service is reachable inside the cluster | Jellyfin, Sonarr, Vaultwarden, Authentik, Grafana, Prometheus, Alertmanager |
| `lan-ingress` | Pi-hole/external-dns + Traefik + backend path works on LAN | `https://vault.homelab`, `https://grafana.homelab` |
| `public` | Cloudflare/Tunnel-facing endpoints work from inside the cluster | `watch.saharserver.com`, `requests.saharserver.com`, `enroll.saharserver.com` |
| `infra-tcp` | Critical infrastructure sockets are reachable | Proxmox API, NFS, Pi-hole DNS, kubelet, k3s API |
| `dns` | Pi-hole can resolve a representative external-dns-managed homelab name | `jellyfin.homelab` via `192.168.50.20` |

### Platform metrics scraping

`apps/base/monitoring/kube-prometheus-stack/homelab-platform-monitors.yaml` adds PodMonitors for:

- Flux controllers
- external-secrets
- cert-manager

### Homelab-specific alert rules

`apps/base/monitoring/kube-prometheus-stack/homelab-prometheusrule.yaml` adds alerts with `hermes_triage="true"` labels:

- `HomelabNodeNotReady`
- `HomelabNodeDiskPressure`
- `HomelabCronJobMissedSchedule`
- `HomelabFluxReconciliationNotReady`
- `HomelabFluxReconciliationStalled`
- `HomelabExternalSecretNotReady`
- `HomelabCertificateExpiresSoon`
- `HomelabProxmoxZFSScrapeDown`
- `HomelabZFSUnhealthy`
- `HomelabZFSHighUsage`

The existing blackbox rules continue to cover probe failures/slowness. The new probes make those rules much broader.

## Hermes integration design

Recommended target architecture:

```text
Prometheus rules + blackbox probes
  ↓
Alertmanager
  ├─ Discord: immediate human notifications
  ├─ Telegram: optional direct critical alerts
  └─ Hermes: triage, investigation, fix plan
```

### Phase 1: Hermes cron poller

Run Hermes on an always-on node, preferably `k3s-worker`, then create a cron job that polls Prometheus/Alertmanager every few minutes.

The cron prompt should:

1. Query active alerts from Prometheus.
2. Filter to `severity=warning|critical` and/or `hermes_triage=true`.
3. Group by alertname/namespace/component.
4. For new or changed alerts, inspect read-only evidence:
   - `kubectl get/describe` for affected resources
   - recent Warning events
   - Flux/HelmRelease/Kustomization status
   - PVC/PV/node state
   - Proxmox SSH checks for storage/VM/Pi-hole alerts
5. Send the user a concise Telegram report with:
   - what is broken
   - impact
   - likely root cause
   - evidence
   - safe next actions
   - whether a write action/PR is recommended

This requires no new public endpoint and is easiest to make reliable.

### Phase 2: Alertmanager webhook to Hermes

After Hermes is stable on `k3s-worker`, add an Alertmanager webhook receiver for alerts with `hermes_triage="true"`.

Expected receiver shape:

```yaml
receivers:
  - name: hermes
    webhook_configs:
      - url: "https://<hermes-webhook-endpoint>/webhooks/alertmanager"
        send_resolved: true
```

Store the URL/token outside Git, e.g. AWS SSM Parameter Store:

```text
/homelab/hermes-alerts/webhook-url
```

Then extend `discord-externalsecret.yaml` to inject that URL into Alertmanager config and add a route:

```yaml
routes:
  - receiver: hermes
    matchers:
      - hermes_triage = "true"
    continue: true
```

`continue: true` keeps Discord delivery working even when Hermes also receives the alert.

### Phase 3: assisted remediation

Hermes should start read-only. For remediation:

- Low-risk: open a GitHub issue/PR or suggest exact commands.
- Medium-risk: ask for approval before reconciling Flux/restarting pods.
- High-risk: never run destructive storage/Proxmox commands without explicit user approval.

## Important limitations

- Public endpoint probes from inside the cluster validate Cloudflare/Tunnel/backend flow, but they are not a true external-client view. Add an outside-LAN checker later for full coverage.
- K3s node certificate warnings surfaced as Kubernetes events today. Prometheus does not currently scrape Kubernetes event objects as first-class metrics; add an event-exporter if you want those warnings converted into alert rules.
- Proxmox host CPU/RAM/disk, SMART, VM/LXC states, and NFS checks need additional exporters or Hermes SSH polling. This PR only adds TCP/ZFS scrape-level coverage for Proxmox.

## Next recommended PRs

1. Add Proxmox `node_exporter`, `smartctl_exporter`, and `prometheus-pve-exporter`.
2. Add a Kubernetes event-exporter so warnings like K3s certificate expiration become Prometheus alerts.
3. Deploy Hermes gateway/triage worker on `k3s-worker` and create the polling cron job.
4. Add Alertmanager webhook routing once the Hermes endpoint and secret exist.
