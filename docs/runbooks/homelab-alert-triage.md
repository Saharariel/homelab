# Homelab alert triage runbook

This runbook is written for both a human operator and Hermes. Hermes should use it as a read-only investigation checklist before proposing fixes.

## General Hermes triage flow

For any firing alert with `hermes_triage="true"`:

1. Identify alert labels: `alertname`, `severity`, `namespace`, `component`, `instance`, `job`, `node`, `pod`, `service`, `probe_group`.
2. Check current alert state in Prometheus and whether Alertmanager has grouped/silenced it.
3. Collect read-only Kubernetes evidence:
   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
   kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -50
   kubectl get kustomizations.kustomize.toolkit.fluxcd.io,helmreleases.helm.toolkit.fluxcd.io -A
   ```
4. If the alert is app-specific, inspect the namespace:
   ```bash
   kubectl -n <namespace> get deploy,statefulset,daemonset,job,cronjob,pod,svc,ingress,pvc
   kubectl -n <namespace> describe pod <pod>
   ```
5. If storage/Proxmox/Pi-hole is implicated, use read-only SSH checks only.
6. Report impact, likely root cause, evidence, and a proposed next action. Ask for approval before mutating anything.

## Node not ready

Alert: `HomelabNodeNotReady`

Read-only checks:

```bash
kubectl describe node <node>
kubectl get pods -A -o wide | grep <node>
ssh <node-alias> 'systemctl status k3s k3s-agent containerd --no-pager; df -h; free -h'
```

Likely causes: node asleep/offline, kubelet/k3s-agent failure, disk pressure, network partition, Proxmox VM issue.

## Node disk pressure

Alert: `HomelabNodeDiskPressure`

Read-only checks:

```bash
kubectl describe node <node>
ssh <node-alias> 'df -h; du -xh /var/lib/rancher /var/lib/containerd 2>/dev/null | sort -h | tail -30'
```

Do not delete images/logs without approval.

## CronJob missed schedule

Alert: `HomelabCronJobMissedSchedule`

Read-only checks:

```bash
kubectl -n <namespace> get cronjob <cronjob> -o yaml
kubectl -n <namespace> get jobs --sort-by=.metadata.creationTimestamp
kubectl -n <namespace> get events --sort-by='.lastTimestamp' | tail -50
```

Check whether the alert is expected for disabled/manual CronJobs before recommending a fix.

## Flux not ready

Alert: `HomelabFluxReconciliationNotReady`

Read-only checks:

```bash
kubectl -n flux-system get gitrepositories,kustomizations,helmrepositories,helmcharts,helmreleases -A
kubectl -n flux-system describe kustomization <name>
kubectl -n <namespace> describe helmrelease <name>
kubectl -n flux-system logs deploy/source-controller --tail=100
kubectl -n flux-system logs deploy/kustomize-controller --tail=100
kubectl -n flux-system logs deploy/helm-controller --tail=100
```

Prefer a GitOps PR for durable fixes.

## Flux stalled

Alert: `HomelabFluxReconciliationStalled`

Same checks as Flux not ready. Collect the exact stalled reason/message before suggesting action.

## ExternalSecret not ready

Alert: `HomelabExternalSecretNotReady`

Read-only checks:

```bash
kubectl -n <namespace> describe externalsecret <name>
kubectl get clustersecretstore aws-parameter-store -o yaml
kubectl -n external-secrets logs deploy/external-secrets --tail=100
kubectl -n <namespace> get pods
```

Likely causes: missing AWS SSM parameter, IAM/IRSA/auth problem, SecretStore unavailable, template error.

## Certificate expiring

Alert: `HomelabCertificateExpiresSoon`

Read-only checks:

```bash
kubectl -n <namespace> describe certificate <name>
kubectl -n <namespace> get certificaterequest,order,challenge
kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

For K3s internal certificate warnings, Prometheus may not see the event until event-exporter is installed. If Kubernetes events report K3s certificate expiration, inspect and plan a controlled K3s restart/rotation window.

## Proxmox ZFS scrape down

Alert: `HomelabProxmoxZFSScrapeDown`

Read-only checks:

```bash
ssh proxmox 'systemctl status zfs_exporter --no-pager; ss -ltnp | grep 9134; zpool status'
kubectl -n monitoring get endpoints prometheus-prometheus
```

Likely causes: exporter stopped, Proxmox unreachable, firewall/network issue.

## ZFS unhealthy

Alert: `HomelabZFSUnhealthy`

Read-only checks:

```bash
ssh proxmox 'zpool status -v; zpool list; smartctl --scan; systemctl status smartmontools --no-pager'
```

Do not run `zpool clear`, detach/replace disks, or scrub/resilver commands without explicit approval.

## ZFS high usage

Alert: `HomelabZFSHighUsage`

Read-only checks:

```bash
ssh proxmox 'zfs list -o name,used,avail,refer,mountpoint; zpool list'
```

Suggest cleanup candidates or expansion, but do not delete files without approval.

## Blackbox probe failed

Alert: `BlackboxProbeFailed`

Check `probe_group`:

- `internal`: app/service/backend problem.
- `lan-ingress`: Pi-hole/external-dns/Traefik/TLS/backend path problem.
- `public`: Cloudflare Tunnel/public DNS/backend ingress problem.
- `infra-tcp`: Proxmox/NFS/Pi-hole/kubelet/API reachability problem.
- `dns`: Pi-hole DNS resolution problem.

Read-only checks:

```bash
kubectl -n monitoring get probe
kubectl -n <namespace> get pod,svc,ingress,endpoints
kubectl -n <namespace> describe pod <pod>
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -50
```

For public endpoint failures, also check cloudflared:

```bash
kubectl -n utils get deploy,pod -l app=cloudflared
kubectl -n utils logs deploy/cloudflared --tail=100
```
