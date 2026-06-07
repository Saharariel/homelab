# RCA: why enabling Cilium KPR / BPF host-routing kills the node (2026-05-30)

**Status:** Root cause identified with hard evidence (worker, captured logs).
Control-plane mechanism strongly inferred (no logs retained from those attempts).

## One-line root cause

Enabling `kube-proxy-replacement: true` with `enable-host-legacy-routing: false`
(BPF host routing) breaks the **host-namespace connection to the kube-apiserver**.
On k3s that path is the agent's local load-balancer at **`127.0.0.1:6444`** →
`192.168.50.19:6443`. Once it breaks, the node can't renew its lease → NotReady;
everything else (NFS wedge on the worker, SSH/API loss on the control plane) is
downstream.

## Hard evidence — worker boot −1 (the 2026-05-30 worker-only KPR test)

Failure order from `journalctl -u k3s-agent -b -1`, before any NFS symptom:

| time | event |
|---|---|
| 11:44:14 | cilium-dfn6b (KPR/`host-legacy-routing=false`) reaches Running |
| **11:44:40** | first fail: `Failed to update lease … Put https://127.0.0.1:6444 … Client.Timeout` |
| 11:44:56 | `Server 192.168.50.19:6443@ACTIVE*->FAILED from failed dial`; `Closing 4 connections to load balancer server`; `TLS handshake timeout`, `unexpected EOF` to `127.0.0.1:6444` |
| 11:45:06–17 | k3s apiserver LB flaps `FAILED↔RECOVERING↔PREFERRED` every few seconds |
| **11:47:26** | NFS `server 192.168.50.10 not responding` begins — **~3 min later** |

So the API-server connection died **~26 s after the eBPF datapath came up**, and
NFS froze ~3 min later. The earlier "it was NFS" conclusion was wrong: NFS was
the last symptom, not the cause. Kernel log in the agent-start window: **no NIC
reset / link flap / driver error** — the break was purely in the eBPF datapath.

## The k3s architecture detail that is the whole story

k3s-agent does **not** dial the apiserver directly. It runs a built-in
load-balancer on loopback; every component connects to it:

```
LISTEN 127.0.0.1:6444  k3s-agent                         # local apiserver LB
ESTAB  127.0.0.1:6444  127.0.0.1:33596                   # agent -> itself
ESTAB  192.168.50.18:58448  192.168.50.19:6443           # LB -> real apiserver
```

Every failure in the log is `https://127.0.0.1:6444/...`. When BPF host routing /
socket-LB take over the host connect()/datapath, this **loopback→apiserver proxy
connection** is mishandled: SYN goes, handshake never completes. The k3s LB marks
the upstream FAILED, lease renewal fails, node → NotReady. On the control plane
the same mechanism breaks host-terminated SSH(:22)/API(:6443) directly → lockout.

## Upstream corroboration

[cilium#27343](https://github.com/cilium/cilium/issues/27343) — "Broken
connectivity when using BPF masquerade and BPF Host Routing": SYN sent, SYN-ACK
never returns, apiserver silently dropped (our exact signature). Documented
triggers/workarounds map onto our history:

- trigger: `bpf.masquerade: true` + **BPF host routing** (`hostLegacyRouting:false`)
- "issue affects **only direct routing**; tunnel/VXLAN works" (we use vxlan — good)
- workarounds: `bpf.hostLegacyRouting: true`, disable bpf.masquerade, use vxlan
- k3s/loopback-apiserver angle: `socketLB.hostNamespaceOnly: true`

Our worker test set `enable-host-legacy-routing: "false"` — the **exact trigger**.
We never tested KPR with `hostLegacyRouting: true` + `socketLB.hostNamespaceOnly:
true`, which is the combination the evidence says should survive.

## Proven vs inferred

- **Proven (worker, logs):** KPR + BPF-host-routing → `127.0.0.1:6444`→apiserver
  breaks in ~30 s → NotReady; NFS wedge is a later side-effect of `hard` mounts.
- **Inferred (control plane, no logs):** same eBPF-breaks-host-terminated-traffic
  mechanism kills SSH/API → instant lockout. Not reproduced; not proven.

## Baseline facts (live, KPR currently OFF)

```
kube-proxy-replacement = false      routing-mode = tunnel / vxlan
bpf-lb-sock = false                 enable-ipv4-masquerade = true (iptables)
enable-host-legacy-routing = (unset -> legacy/default)
```

Cluster topology constraints that matter for any retry:
- traefik (1 replica) and coredns (1 replica) run **only on the control plane**;
  a control-plane datapath failure takes down all ingress (incl. jellyfin) + DNS.
- worker `hard`-mounts /tank/{data,configs,photos} from 192.168.50.10 → any
  host→NFS break wedges the node (D-state). Independent landmine.

## If KPR is ever attempted (config the evidence points to)

Keep what works, avoid the regression-prone path:
- **`kubeProxyReplacement: true`** + `k8sServiceHost/Port`
- **`bpf.hostLegacyRouting: true`** (do NOT enable BPF host routing — that's the
  #27343 trigger)
- **`socketLB.hostNamespaceOnly: true`** (cm key `bpf-lb-sock-hostns-only`;
  stops socket-LB rewriting the host loopback→apiserver connection; kernel ≥5.7,
  have 6.8)
- keep **tunnel/vxlan**; do NOT add `bpf.masquerade: true` or `endpointRoutes`
- prerequisites: traefik + coredns HA across both nodes; disable k3s
  servicelb+traefik and migrate the LB IP to Cilium L2 (KPR also wants this)

Test plan: `docs/runbooks/cilium-kpr-test-plan.md`.

Supersedes `cilium-kpr-migration.md` (its same-node conntrack-invalid premise was
disproven; counter stayed at 0).
