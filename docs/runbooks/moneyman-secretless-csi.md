# Moneyman secretless runtime secret mount

This runbook documents the moneyman migration from an ExternalSecret-created Kubernetes Secret to a Secrets Store CSI Driver mount backed by AWS Systems Manager Parameter Store.

## Goal

The sensitive moneyman config should not be stored as a Kubernetes Secret object. After this migration, the CronJob reads the config from `/secrets/config.json`, but that file is mounted at pod runtime by the CSI driver.

This prevents the direct failure mode:

```bash
kubectl get secret moneyman-secret -n moneyman -o yaml
```

because the desired end state has no `moneyman-secret` Kubernetes Secret.

## Source of truth

AWS Systems Manager Parameter Store:

```text
/homelab/moneyman/MONEYMAN_CONFIG
```

Recommended AWS-side hardening:

- Store it as a SecureString.
- Encrypt it with a dedicated customer-managed KMS key.
- Grant decrypt/read only to the moneyman workload identity.
- Enable CloudTrail auditing for `ssm:GetParameter`, `ssm:GetParameters`, and `kms:Decrypt`.

## Kubernetes objects in this repo

- `controllers/base/secrets-store-csi-driver/`: installs the AWS provider chart, which also installs the Secrets Store CSI Driver dependency.
- `apps/base/utils/moneyman/secretproviderclass.yaml`: maps `/homelab/moneyman/MONEYMAN_CONFIG` to the mounted file `config.json` with mode `0400`.
- `apps/base/utils/moneyman/cronjob.yaml`: mounts the CSI volume at `/secrets` and keeps `MONEYMAN_CONFIG_PATH=/secrets/config.json`.

The SecretProviderClass intentionally does **not** define `secretObjects`; enabling that would sync the value back into a Kubernetes Secret and undo the purpose of this migration.

## Required pre-merge check

The AWS provider must have a way to authenticate to AWS from this self-managed K3s cluster.

For an EKS cluster this is usually IRSA or EKS Pod Identity. This homelab is K3s, so verify the chosen workload identity path before merging. A good target is:

- one AWS IAM role/user/policy scoped only to `/homelab/moneyman/*`
- KMS decrypt only for the moneyman KMS key
- no access to unrelated `/homelab/*` parameters

If workload identity is not ready, the CronJob pod will fail at volume mount time.

## Post-merge cleanup

After Flux applies the migration and a test moneyman Job succeeds, delete the old Kubernetes Secret if it remains from the previous ExternalSecret flow:

```bash
kubectl delete secret moneyman-secret -n moneyman --ignore-not-found
kubectl delete externalsecret moneyman-secret -n moneyman --ignore-not-found
```

Then verify that the direct Kubernetes Secret read path is gone:

```bash
kubectl get secret moneyman-secret -n moneyman
# expected: NotFound
```

## Verification

Run a manual Job from the CronJob:

```bash
kubectl create job -n moneyman --from=cronjob/moneyman moneyman-manual-$(date +%s)
```

Watch status without printing secrets:

```bash
kubectl get pods,jobs -n moneyman
kubectl describe pod -n moneyman -l app=moneyman
```

Only inspect logs after confirming the app does not print config or credentials.

## Remaining threat model

This removes the Kubernetes Secret object, but plaintext still exists inside the moneyman pod while it runs. Users with permission to edit the CronJob, create pods using the same SecretProviderClass, exec/debug into pods, or access node filesystems can still steal the secret. Keep normal kubectl access read-only and keep cluster-admin as break-glass only.
