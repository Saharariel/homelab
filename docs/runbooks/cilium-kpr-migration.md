> ⚠️ **SUPERSEDED** by `cilium-kpr-rca-2026-05-30.md`. Its same-node
> conntrack-invalid premise was disproven (counter stayed at 0). Do not follow.

# Cilium kubeProxyReplacement Migration Runbook

Migrates Cilium from `kubeProxyReplacement: false` + `Host: Legacy` routing → `kubeProxyReplacement: true` + `Host: BPF`. This fixes same-node pod→host TCP (conntrack-invalid issue under Legacy mode) and the Hubble UI relay reconnect loop.

**Estimated time:** 60-90 minutes if smooth, allow 2 hours.

**Risk:** Medium. Both prior attempts locked the cluster out. Safety nets in this runbook are designed so the worst case is a 10-minute auto-revert on one node.

---

## Before the day

- [ ] Read this runbook end-to-end
- [ ] Make sure Dell Vostro (control plane) has keyboard + monitor available
- [ ] Make sure Proxmox web access works (`https://192.168.50.10:8006`) — test login
- [ ] Make sure `ssh k3s-laptop` and `ssh k3s-worker` both work
- [ ] Confirm `kubectl get nodes` shows both nodes Ready
- [ ] Confirm no critical things are running that would be hurt by a 10-min worker outage

## T-15 min: pre-flight setup

Open these terminals and keep them open:

1. **Terminal A** — `ssh k3s-laptop` (control plane SSH)
2. **Terminal B** — `ssh k3s-worker` (worker SSH)
3. **Terminal C** — your workstation (kubectl access)
4. **Terminal D** — Proxmox web UI, worker VM 103 console tab open

Physical: keyboard/monitor plugged into the Dell Vostro, ready to switch input if needed.

### Capture baseline state

In Terminal C:
```bash
mkdir -p ~/cilium-migration-$(date +%Y%m%d)
cd ~/cilium-migration-$(date +%Y%m%d)

# Backup configmap and HelmRelease
kubectl get cm -n kube-system cilium-config -o yaml > cilium-config.before.yaml
kubectl get helmrelease -n kube-system cilium -o yaml > helmrelease.before.yaml

# Snapshot pod state
kubectl get pods -A -o wide > pods.before.txt

# Snapshot cilium status from both agents
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium status > cilium-status.before.cp.txt
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=worker-node-1 -o jsonpath='{.items[0].metadata.name}') -- cilium status > cilium-status.before.worker.txt
```

Verify the baseline:
- Both `cilium status` outputs show `KubeProxyReplacement: False`, `Host: Legacy`
- All pods you care about are `Running`

### Suspend Flux

In Terminal C:
```bash
flux suspend kustomization controllers
flux suspend helmrelease -n kube-system cilium
```

This prevents Flux from fighting us mid-migration. We'll restore at the end.

### Pre-position recovery commands

Keep this block visible in a separate window or sticky note. **Memorize the first command — it's the panic button.**

```bash
# === PANIC: revert configmap to safe (Legacy) and restart cilium ===
sudo k3s kubectl -n kube-system patch configmap cilium-config --type merge -p '{"data":{"kube-proxy-replacement":"false","enable-host-legacy-routing":"true","bpf-masquerade":"false","enable-bpf-masquerade":"false"}}'
sudo k3s kubectl -n kube-system rollout restart daemonset/cilium

# === If BPF programs stuck, force-detach from NIC ===
sudo bpftool net  # find link_id for enp6s18 ingress/egress
sudo bpftool link detach id <ID>

# === If K3s broken too, revert config.yaml ===
sudo sed -i '/disable-kube-proxy/d' /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s
```

For worker via Proxmox guest-exec (when SSH dies):
```bash
ssh proxmox "qm guest exec 103 -- /bin/bash -c '<command>'"
```

---

## Phase 1: Arm dead-man switches (5 min)

This is the most important safety net. If the cluster goes silent for 10 min, these auto-revert everything.

### On control plane (Terminal A)

```bash
# Confirm at is installed
which at || sudo apt install -y at
sudo systemctl enable --now atd

# Save current configmap to a path the at-job can read
sudo k3s kubectl get cm -n kube-system cilium-config -o yaml | sudo tee /root/cilium-config.backup.yaml > /dev/null

# Schedule auto-revert in 15 min
echo "k3s kubectl apply -f /root/cilium-config.backup.yaml && k3s kubectl -n kube-system rollout restart daemonset/cilium" | sudo at now + 15 minutes 2>&1 | tee /tmp/at-job-cp.txt

# Note the job ID (e.g. "job 5 at ...")
sudo atq
```

### On worker (Terminal B)

```bash
which at || sudo apt install -y at
sudo systemctl enable --now atd

# The worker doesn't need to patch the configmap directly — it pulls from API.
# But we can stage a "kick the agent" job in case the cm is fine but the local agent stuck:
echo "systemctl restart k3s-agent" | sudo at now + 15 minutes 2>&1 | tee /tmp/at-job-worker.txt
sudo atq
```

**Both jobs are armed.** If you go quiet for 15 min, they fire. To cancel before fire: `sudo atrm <id>`.

---

## Phase 2: Test on worker via CiliumNodeConfig (15 min)

This is the blast-radius limiter. Worker gets the new config; control plane stays safe.

### Apply CiliumNodeConfig

In Terminal C, save this as `worker-kpr-test.yaml`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNodeConfig
metadata:
  name: kpr-test-worker
  namespace: kube-system
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: worker-node-1
  defaults:
    kube-proxy-replacement: "true"
    enable-host-legacy-routing: "false"
    k8s-service-host: "192.168.50.19"
    k8s-service-port: "6443"
```

Apply:
```bash
kubectl apply -f worker-kpr-test.yaml
```

### Restart only the worker's cilium-agent

```bash
WORKER_CILIUM=$(kubectl get pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=worker-node-1 -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n kube-system "$WORKER_CILIUM"
```

Wait ~60s. Watch in Terminal C:
```bash
kubectl get pods -n kube-system -l k8s-app=cilium -w
```

### Verify worker

In Terminal C:
```bash
WORKER_CILIUM=$(kubectl get pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=worker-node-1 -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $WORKER_CILIUM -- cilium status
```

Look for:
- `KubeProxyReplacement: True`
- `Host: BPF`
- `Cilium: Ok`
- `Cluster health: 2/2 reachable`

Test same-node pod→host TCP (the original symptom):
```bash
kubectl run kpr-test --image=busybox --rm -i --restart=Never \
  --overrides='{"spec":{"nodeName":"worker-node-1"}}' \
  -- nc -zvw3 192.168.50.18 22
```
Should print "open" instantly. If it works → the fix is working.

Test cross-node still works:
```bash
kubectl run kpr-test2 --image=busybox --rm -i --restart=Never \
  --overrides='{"spec":{"nodeName":"worker-node-1"}}' \
  -- nc -zvw3 192.168.50.19 6443
```
Should also print "open".

Test worker SSH still works (Terminal B should still be alive). Test pods on worker still scheduling. Test `kubectl logs` against a worker pod still works.

### If worker is broken

- Try `kubectl delete ciliumnodeconfig -n kube-system kpr-test-worker` from Terminal C
- Then `kubectl delete pod -n kube-system <worker-cilium-pod>` so it reloads without the override
- If kubectl from worker pods is broken but control plane kubectl works, the dead-man switch on the WORKER will kick it at 15 min anyway
- If kubectl from control plane is somehow affected: dead-man switch on control plane handles it

### Cancel worker dead-man if all good

In Terminal B:
```bash
sudo atq      # list jobs
sudo atrm <id>
```

**Stop here for at least 10 minutes** and watch pods. If anything regresses (hubble-relay still loops, weird new errors, etc.), revert before continuing.

---

## Phase 3: Apply globally via HelmRelease (15 min)

Once worker is verified stable for 10+ minutes, promote the change to the global HelmRelease.

### Edit `controllers/base/cilium/helmrelease.yaml`

Add under `values:`:
```yaml
    kubeProxyReplacement: true
    k8sServiceHost: 192.168.50.19
    k8sServicePort: 6443
    bpf:
      hostLegacyRouting: false
```

**Do NOT add `bpf.masquerade` or `endpointRoutes.enabled` yet** — those broke things last time. Add them in a separate change later if you want them, after this is stable.

The full values block should look like:
```yaml
  values:
    kubeProxyReplacement: true
    k8sServiceHost: 192.168.50.19
    k8sServicePort: 6443
    bpf:
      hostLegacyRouting: false
    ipam:
      operator:
        clusterPoolIPv4PodCIDRList: "10.42.0.0/16"
    hubble:
      relay:
        enabled: true
      ui:
        enabled: true
      metrics:
        enabled:
          - dns
          - drop
          - tcp
          - flow
          - port-distribution
          - icmp
          - httpV2
```

### Remove the test CiliumNodeConfig

The HelmRelease now has the same settings; the CNC override is redundant:
```bash
kubectl delete ciliumnodeconfig -n kube-system kpr-test-worker
```

### Commit, push, and reconcile

```bash
cd ~/repos/homelab
git add controllers/base/cilium/helmrelease.yaml
git commit -m "fix(cilium): enable kubeProxyReplacement and BPF host routing"
git push

flux resume helmrelease -n kube-system cilium
flux reconcile helmrelease -n kube-system cilium
```

### Watch the rollout

```bash
kubectl rollout status ds/cilium -n kube-system
kubectl get pods -n kube-system -l k8s-app=cilium -w
```

The control plane's cilium-agent will restart with the new settings. Watch for it to come back Ready.

### Verify both nodes

```bash
for pod in $(kubectl get pod -n kube-system -l k8s-app=cilium -o name); do
  echo "=== $pod ==="
  kubectl exec -n kube-system $pod -- cilium status | grep -E "KubeProxyReplacement|Host:|Cluster health"
done
```

Both should show `KubeProxyReplacement: True` and `Host: BPF`. Cluster health `2/2`.

**Stop here for another 10 minutes.** Verify pods are still happy. Test services.

---

## Phase 4: Disable K3s kube-proxy (10 min)

Now that Cilium is handling everything, retire K3s's kube-proxy.

### Update config on control plane (Terminal A)

```bash
sudo cp /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.before-kpr

# Append the disable flag
echo "disable-kube-proxy: true" | sudo tee -a /etc/rancher/k3s/config.yaml

cat /etc/rancher/k3s/config.yaml
```

Should look like:
```yaml
write-kubeconfig-mode: "644"
flannel-backend: "none"
disable-network-policy: true
disable-kube-proxy: true
```

### Restart K3s server

```bash
sudo systemctl restart k3s
```

Wait ~30-60s. Then in Terminal C:
```bash
kubectl get nodes
kubectl get pods -n kube-system
```

If kubectl works and nodes are Ready, kube-proxy is successfully retired. Services should still work because Cilium is handling them.

### Verify

```bash
# Hit a ClusterIP service from a fresh pod
kubectl run svc-test --image=busybox --rm -i --restart=Never -- wget -qO- --timeout=5 http://hubble-relay.kube-system.svc:80 2>&1 | head -3
# (it'll fail with 404 or similar but should CONNECT)

# Confirm no kube-proxy processes
ssh k3s-laptop "ps auxww | grep kube-proxy | grep -v grep"
# Should return nothing
```

### Worker node

The worker's k3s-agent inherits service handling from the server. No config change needed on worker — but `sudo systemctl restart k3s-agent` is a good idea to make sure its kube-proxy is also gone.

---

## Phase 5: Wrap-up

### Disarm dead-man switches

In Terminals A and B:
```bash
sudo atq
sudo atrm <id>   # all of them
```

### Resume Flux

In Terminal C:
```bash
flux resume kustomization controllers
flux reconcile kustomization controllers
```

### Verify the fixes worked

```bash
# Original symptom: Hubble UI flapping due to relay can't reach local cilium-agent
kubectl logs -n kube-system -l app.kubernetes.io/name=hubble-relay --tail=20
# Should NOT show "No connection to peer" or "FlowStream has been stopped"

# Open Hubble UI and check metrics tab — should populate now
```

### Capture after-state

```bash
cd ~/cilium-migration-$(date +%Y%m%d)
kubectl get pods -A -o wide > pods.after.txt
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium status > cilium-status.after.cp.txt
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=worker-node-1 -o jsonpath='{.items[0].metadata.name}') -- cilium status > cilium-status.after.worker.txt

diff pods.before.txt pods.after.txt | head -50
```

---

## Recovery procedures by phase

### Phase 2 (worker test) fails

- From control plane (still healthy): `kubectl delete ciliumnodeconfig -n kube-system kpr-test-worker`
- `kubectl delete pod -n kube-system <worker-cilium-pod>`
- Worker's cilium-agent reloads with global (Legacy) config

### Phase 3 (global rollout) fails

- `git revert HEAD && git push` — push the revert
- `flux reconcile helmrelease -n kube-system cilium`
- If Flux can't run because cluster is broken, dead-man switch fires at 15 min

### Phase 4 (K3s kube-proxy disable) fails

- On control plane via console: `sudo cp /etc/rancher/k3s/config.yaml.before-kpr /etc/rancher/k3s/config.yaml`
- `sudo systemctl restart k3s`

### Full lockout (can't kubectl, can't SSH)

- Wait 15 minutes for dead-man switches to fire
- If they don't fire: physical console on Dell Vostro, Proxmox guest-exec on worker
- Run the panic button commands from "pre-position recovery commands" section

---

## Notes

- This runbook intentionally **does not** enable `bpf.masquerade: true` or `endpointRoutes.enabled: true`. Those caused issues in prior attempts. Add them in a separate change after this one is stable, if you actually need them (you probably don't — they're optimizations, not requirements).
- The 15-minute dead-man timeout can be increased if you need more verify time, but don't make it too long — the whole point is bounded blast radius.
- If `cilium` chart's API for these options changes between versions, check the chart docs before applying. Version pinned in helmrelease.yaml at time of writing: `1.x` (latest 1.19.x).
