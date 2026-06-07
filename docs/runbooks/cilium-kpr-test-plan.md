# Falsifiable test: can KPR survive on this stack?

**Goal:** test ONE hypothesis with a clear pass/fail, not roll out KPR.

**Hypothesis (from RCA `cilium-kpr-rca-2026-05-30.md`):** the lockouts were caused
by **BPF host routing** and **host-namespace socket-LB** breaking the k3s agent's
`127.0.0.1:6444 -> apiserver` path. KPR with both mitigations ON
(`bpf.hostLegacyRouting: true` + `socketLB.hostNamespaceOnly: true`, tunnel/vxlan,
no bpf.masquerade) should keep that path healthy.

**Pass:** after the worker agent restarts in KPR mode, the `127.0.0.1:6444` path
stays healthy (no `failed dial` / `TLS handshake timeout`) and the worker stays
Ready for 10 min. **Fail:** any of the RCA's failure signatures reappear.

**Blast radius:** worker only, via `CiliumNodeConfig`. Control plane untouched.
Worst case = worker NotReady for ~10 min, auto-reverted by dead-man switch +
recoverable by VM reboot (proven on 2026-05-30). **Do not run a control-plane
test** until traefik + coredns are HA (jellyfin/ingress + DNS SPOF).

---

## Pre-flight

Terminals: A=`ssh k3s-worker`, B=`ssh k3s-laptop` (control plane), C=kubectl,
D=Proxmox console for VM 103 (worker) — `ssh root@192.168.50.10` then
`qm terminal 103` / web console (guest-exec works as root).

Baseline capture (C):
```
mkdir -p ~/kpr-test-$(date +%Y%m%d) && cd ~/kpr-test-$(date +%Y%m%d)
kubectl get cm -n kube-system cilium-config -o yaml > cm.before.yaml
kubectl get pods -A -o wide > pods.before.txt
```

## Phase 1 — arm dead-man switch (on the WORKER, acts on the worker)

The break makes the worker unable to reach the API, so the revert must run
**locally on the worker** (not via kubectl). It removes the CNC override by
restarting k3s-agent after deleting the CNC from the control plane.

On control plane (B) — stage the CNC delete as the recovery, and on worker (A)
arm a local agent-restart that also clears the per-node config cache:

```
# Worker (A): if we go silent 12 min, restart agent (reloads cilium w/o CNC once
# the CNC is gone from the API). Also works if API is reachable again by then.
echo 'systemctl restart k3s-agent' | sudo at now + 12 minutes ; sudo atq
```
```
# Control plane (B): stage CNC deletion as a one-shot in 12 min as the real undo.
echo 'k3s kubectl delete ciliumnodeconfig -n kube-system kpr-test --ignore-not-found && k3s kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=worker-node-1' | sudo at now + 12 minutes ; sudo atq
```

Keep Terminal A's SSH session OPEN (established TCP survives eBPF reattach — it
did on 2026-05-30; that's how we recovered).

## Phase 2 — apply worker-only KPR with BOTH mitigations

On control plane (B):
```
cat > /root/kpr-test.yaml <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNodeConfig
metadata:
  name: kpr-test
  namespace: kube-system
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: worker-node-1
  defaults:
    kube-proxy-replacement: "true"
    k8s-service-host: "192.168.50.19"
    k8s-service-port: "6443"
    # KEEP legacy host routing (NOT BPF host routing) — #27343 trigger avoided
    enable-host-legacy-routing: "true"
    # socket-LB on, but NOT in host namespace — protects 127.0.0.1:6444->apiserver
    bpf-lb-sock: "true"
    bpf-lb-sock-hostns-only: "true"
    # do NOT set bpf-masquerade / endpoint-routes
EOF
k3s kubectl apply -f /root/kpr-test.yaml
k3s kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=worker-node-1
```

## Phase 3 — watch the decisive signal (the 127.0.0.1:6444 path)

On worker (A), immediately:
```
journalctl -u k3s-agent -f | grep -iE 'load balancer|failed dial|127.0.0.1:6444|TLS handshake|lease'
```

- **PASS:** within ~90 s the new cilium pod is Running and the above shows NO
  `failed dial` / `TLS handshake timeout`; `kubectl get node worker-node-1` stays
  Ready. Confirm KPR active:
  `kubectl -n kube-system exec <worker-cilium> -- cilium status | grep -E 'KubeProxyReplacement|Host Routing'`
  → want `KubeProxyReplacement: True`, `Host Routing: Legacy`.
- **FAIL:** `Server 192.168.50.19:6443@...->FAILED from failed dial` or
  `TLS handshake timeout` to `127.0.0.1:6444` reappears, or node goes NotReady.
  → hypothesis disproven; KPR is not viable on this stack. Revert now (Phase 4).

Also re-test the original pod->node-IP symptom while up (proves KPR would even
help): from a pod on the worker, `nc -zvw3 192.168.50.18 9100` and `:22`.

## Phase 4 — revert (either outcome)

On control plane (B):
```
k3s kubectl delete ciliumnodeconfig -n kube-system kpr-test
k3s kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=worker-node-1
```
Then disarm the at-jobs: `sudo atq` / `sudo atrm <id>` on BOTH A and B.
If the worker is wedged: `ssh root@192.168.50.10 'qm reset 103'` (reboot VM;
proven recovery). The agent comes back in the global (Legacy, KPR-off) config.

## Interpreting the result

- **PASS** → the RCA mitigations work; KPR is viable. Next step is a separate
  effort: HA traefik+coredns, servicelb/traefik->Cilium L2, then promote to the
  HelmRelease and the control plane (with console standby). NOT in this test.
- **FAIL** → KPR confirmed dead on this kernel/k3s/Cilium combo even with the
  documented mitigations; stop pursuing it. Keep the hostNetwork workarounds
  (PR #201). Capture the new k3s-agent log window and compare to the RCA.

## Note on what this does NOT cover

- Control-plane behavior (SSH/API loss) remains inferred until tested there,
  which requires the HA prerequisites above.
- etcd metrics (separate; needs k3s `--etcd-expose-metrics=true`).
