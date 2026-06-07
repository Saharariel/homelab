# Server Hub — setup runbook

Server Hub is the self-service onboarding + user-management app for Jellyfin. App source
lives in `~/repos/server-hub` (image: `ghcr.io/saharariel/server-hub`). Kubernetes
manifests are in `apps/base/utils/server-hub/` (prod overlay in
`apps/production/utils/server-hub/`).

These are the **one-time, out-of-band** steps. The app drives Authentik at runtime via
its API; Cloudflare Access is managed manually (step 3). Nothing here is in Git except
the manifests.

## 1. AWS Parameter Store

Create these SecureString parameters (consumed by the `server-hub-secret`
ExternalSecret). Generate `SECRET_KEY` with
`python -c "import secrets; print(secrets.token_urlsafe(48))"`.

| Parameter | Value |
| --- | --- |
| `/homelab/server-hub/SECRET_KEY` | long random string |
| `/homelab/server-hub/AUTHENTIK_API_TOKEN` | token of the scoped service account (step 2) |
| `/homelab/server-hub/AUTHENTIK_JELLYFIN_GROUP_ID` | UUID of the Jellyfin LDAP group |
| `/homelab/server-hub/AUTHENTIK_ENROLLMENT_FLOW_SLUG` | slug of the 2FA enrollment flow (e.g. `enroll-2fa`) |
| `/homelab/server-hub/JELLYFIN_API_KEY` | Jellyfin API key (step 4) |

Cloudflare parameters are **optional** and off by default (perimeter access is managed
manually — see step 3). Add `CF_API_TOKEN`, `CF_ACCOUNT_ID`, `CF_ACCESS_POLICY_ID` and
uncomment the matching keys in `externalsecret.yaml` only if you later want the read-only
access column in the dashboard.

URLs (`ENROLL_BASE_URL`, `WATCH_URL`, `TV_URL`, `AUTHENTIK_URL`, `JELLYFIN_URL`) are set
as plain env in the Deployment and need no parameters.

## 2. Authentik

1. Create a **service account** (Directory -> Users, type "Service account") and give it
   permission to create/manage users in the Jellyfin group only — not full admin.
   Create an **App password / API token** for it -> `AUTHENTIK_API_TOKEN`.
2. Find the **Jellyfin group UUID** (Directory -> Groups) -> `AUTHENTIK_JELLYFIN_GROUP_ID`.
   This must be the group the LDAP outpost maps to Jellyfin access.
3. Ensure a **2FA enrollment flow** exists (a flow with a TOTP-authenticator stage).
   Note its slug -> `AUTHENTIK_ENROLLMENT_FLOW_SLUG`. The wizard links users to
   `https://auth.${BASE_DOMAIN}/if/flow/<slug>/`.
4. (Recommended) Style that flow in **Hebrew / RTL**: set Hebrew prompt labels and add
   RTL custom CSS on the brand/flow so the QR step reads naturally.

## 3. Cloudflare (perimeter access — managed manually)

Access is controlled by **you**, by hand, for security. The app does not change Cloudflare.

1. Add a **public hostname** `enroll.${BASE_DOMAIN}` to the tunnel, pointing at the
   traefik `websecure` service (same as `watch.`/`tv.`).
2. Put `enroll.${BASE_DOMAIN}` behind the **same Cloudflare Access email policy** that
   gates `watch.${BASE_DOMAIN}`. Because they share one policy, granting an email unlocks
   both the wizard and Jellyfin.
3. **Onboarding step:** before sending an invite, add the user's email to that Access
   policy. Then create the invite in the hub and share the link. (Removing the email later
   revokes both enroll and Jellyfin access.)
4. *(Optional, future)* To see a read-only "access" column in the dashboard, create a
   policy-scoped **API token** (`Account -> Access: Apps and Policies -> Edit`), set
   `CF_API_TOKEN` / `CF_ACCOUNT_ID` / `CF_ACCESS_POLICY_ID`, and uncomment those keys in
   `externalsecret.yaml`. The app still never writes to Cloudflare.

## 4. Jellyfin

1. Create an **API key** (Dashboard -> API Keys) -> `JELLYFIN_API_KEY`.
2. Enable **Quick Connect** (Dashboard -> General) so TV users approve a 6-digit code
   instead of typing a password on a remote.

## 5. Admin access (LAN)

- Point `hub.homelab` at the cluster (local DNS / hosts) — the admin ingress listens on
  the traefik `web` entrypoint and is **not** in the tunnel.
- Defense-in-depth (chosen): put the admin ingress behind **Authentik forward-auth**.
  Create a traefik `Middleware` for the Authentik proxy/forward-auth outpost in the
  `utils` namespace, then uncomment the `router.middlewares` annotation in
  `apps/base/utils/server-hub/ingress.yaml`.

## 6. First deploy

1. In `~/repos/server-hub`, push a release tag so CI publishes the image:
   `git tag v0.1.0 && git push origin v0.1.0` (the `image` tag in `deployment.yaml` is
   pinned to `v0.1.0`; Renovate manages later bumps).
2. Flux auto-discovers `apps/production/utils/server-hub/`. Reconcile and verify:
   `flux reconcile kustomization apps --with-source`, then check the pod is Ready and the
   `server-hub-secret` ExternalSecret has synced.

## Verify end-to-end

- From LAN open `http://hub.homelab` -> dashboard lists users (in English).
- Confirm `/admin` on `enroll.${BASE_DOMAIN}` returns 404 (host isolation).
- Add a throwaway email to the shared Access policy, create an invite, open the link in a
  fresh browser, and complete the (Hebrew) wizard; confirm the user appears in Authentik
  and can log into Jellyfin. Then delete the throwaway user from the dashboard and remove
  its email from the Access policy.
