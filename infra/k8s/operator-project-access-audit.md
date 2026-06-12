# Operator Project-Access Audit + Deployment Runbook

How operators access customer projects after the reason-gated refactor, how to
reconstruct an access event after the fact, and what has to be provisioned for
the flow to work.

An operator who isn't a member of a customer account no longer gets blanket
access. Instead they justify access at `ops.tuist.dev`, which mints a short-lived
**signed grant** the customer `server/` verifies offline. Read access is
self-serve (reason only); **admin** access ("sign in as admins") goes through the
**same Slack JIT approval** as a kubectl write. A valid grant also bypasses the
customer's SSO enforcement, which is how SSO-enforced orgs become reachable.

## What you need upfront

- **Grant ID** (`jti` on the token) = the integer PK of the `project_access_grants`
  row in tuist-ops's Postgres. Stable join key across trails.
- **Time window**: `project_access_grants.expires_at` minus the tier TTL gives the
  live window. Anything the operator did against that account/project in the window
  was authorized by the grant.
- **Identities**: `requester_email` = the operator's `@tuist.dev` Google Workspace
  identity (from Pomerium's `X-Pomerium-Claim-Email`). `approver_email`/`approver_slack_id`
  (admin tier only) is the second human.

## Trail 1: Slack thread (admin tier only)

`project_access_requests.slack_channel_id` + `slack_message_ts` resolves to the
approval card, updated through the lifecycle (operator, account, reason, approver,
outcome). Read-tier access never posts to Slack — it lives only in trails 2 and 3.

```sql
-- on tuist-ops's Postgres (production cluster):
SELECT requester_email, account_handle, tier, reason,
       approver_email, approver_slack_id, slack_channel_id, slack_message_ts
FROM project_access_requests
WHERE id = (SELECT request_id FROM project_access_grants WHERE id = $GRANT_ID);
```

## Trail 2: tuist-ops Postgres

The `project_access_requests` + `project_access_grants` rows are the lifecycle of
record: who asked, why, which tier, who approved, when it expired.

```sql
SELECT g.id, g.requester_email, g.account_handle, g.tier, g.reason,
       g.expires_at, g.status, r.approved_at, r.approver_email
FROM project_access_grants g
JOIN project_access_requests r ON r.id = g.request_id
WHERE g.id = $GRANT_ID;
```

## Trail 3: customer server access log

Every request the operator made under the grant is in the customer server's
access log with their `@tuist.dev` email and the path. The grant's `jti` is the
join key back to trail 2. (Apiserver-style per-field audit of what they changed is
a separate follow-up.)

## Security properties

- **Default-deny.** No deploy-time operator allowlist. Eligibility to be *routed*
  to the reason form is "confirmed `@tuist.dev` email authenticated via Google" —
  a routing heuristic, not the boundary. The boundaries are Pomerium/Google-OIDC at
  ops and the server's offline grant verification.
- **EdDSA-strict verification.** The server verifies with `JOSE.JWT.verify_strict(_, ["EdDSA"], _)`
  only — `none`/`HS256` confusion tokens are rejected. `iss`/`aud` are pinned per
  environment, `exp - iat` is capped, and a future-dated `iat` is rejected (which also
  caps absolute expiry), so a compromised signer can't mint a long-lived or cross-env grant.
- **Grant is bound to the operator, not a bearer.** The server stores/honours a grant
  only for a session that is a confirmed `@tuist.dev` operator, Google-authenticated,
  whose email matches the token `sub` (case-insensitive) — at acceptance, at every
  `ops_access`/`ops_write_access` check, and at the SSO bypass. A leaked
  `?operator_grant=` URL replayed by another session attaches nothing and authorizes
  nothing.
- **Verified Pomerium identity at ops.** tuist-ops derives the requester from the
  `X-Pomerium-Jwt-Assertion` signature (`TuistOps.Pomerium`, ES256-strict, `aud`/`exp`
  checked, public key pinned) — NOT the forgeable `X-Pomerium-Claim-Email` header. A
  request that didn't pass through Pomerium (e.g. a raw-tailnet client) carries no
  verified identity and is rejected, so it can't mint a grant or forge an audit row.
  A cheap `@tuist.dev` domain check on the requester is a further backstop.
- **No bearer leakage.** The `?operator_grant=` token is stripped from the URL by a
  redirect before any page renders or any observability plug logs the query string.
- **Decoupled.** The server never calls ops at request time; a customer-facing
  outage doesn't block operator access and vice-versa.
- **Revocation** = short TTL (re-checked every request) + signing-key rotation as
  the break-glass (invalidates all outstanding grants at once).

## Deployment runbook (manual, not automated)

1. **Generate the Ed25519 keypair** (one pair, rotated to revoke all grants):

   ```sh
   openssl genpkey -algorithm ed25519 -out operator_grant_key.pem
   openssl pkey -in operator_grant_key.pem -pubout -out operator_grant_pub.pem
   ```

2. **Private key → ops.** Put the private PEM in the `TUIST_OPS_BOT` 1P item under
   field `project_access_signing_key` (rendered to `PROJECT_ACCESS_SIGNING_KEY` by
   `infra/helm/tuist-ops/templates/externalsecret.yaml`).

3. **Public key → server.** Set `TUIST_OPERATOR_GRANT_PUBLIC_KEY` (the public PEM)
   on the customer server. Optionally pin `TUIST_OPERATOR_GRANT_AUDIENCE` per env
   (defaults to `tuist-server`) — it must match ops's `OPERATOR_GRANT_AUDIENCE`.
   The server also reads `TUIST_OPS_REASON_FORM_URL` (default
   `https://ops.tuist.dev/grants/new`) and `TUIST_OPERATOR_EMAIL_DOMAIN`
   (default `tuist.dev`).

4. **Front `ops.tuist.dev/grants/*` + `/audit*` with Pomerium, and wire the assertion
   key.** tuist-ops no longer trusts the bare `X-Pomerium-Claim-Email` header; it
   verifies the `X-Pomerium-Jwt-Assertion` signature (`TuistOps.Pomerium`). So the
   ops HTML surface fails closed until Pomerium fronts it AND the signing key is wired
   — that is the prerequisite for turning the server redirect on
   (`TUIST_OPS_REASON_FORM_URL`, off by default). Note: **Pomerium is NOT deployed in
   front of ops today.** The per-env Pomerium in each workload cluster fronts only the
   kubectl gateway (`kube-<env>.tuist.dev` → kube-impersonator); the tuist-ops public
   ingress routes only `/webhooks/slack/*`, and `/grants` is currently reachable only
   over the raw tailnet (no assertion → 401 with this change). To stand it up:

   All the chart plumbing is in place behind `opsRoute.enabled` (default false): the
   three Pomerium routes, the `SIGNING_KEY` wiring, the `ops.tuist.dev` host on the
   Pomerium Ingress (TLS + rule), and the `POMERIUM_JWT_PUBLIC_KEY` / `POMERIUM_AUDIENCE`
   env on tuist-ops. Nothing is enabled by default — the cutover is the steps below, and
   only step (a) needs work outside the repo:

   a. **Generate + store Pomerium's signing key** (the one out-of-band secret op).
      An EC P-256 key, base64-PEM:

      ```sh
      openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out pomerium_signing.pem
      base64 -w0 pomerium_signing.pem                       # → 1P field `signing_key`
      openssl pkey -in pomerium_signing.pem -pubout -out pomerium_pub.pem
      ```

      Put the base64 value in the `POMERIUM_<ENV>` 1P item under `signing_key`. The
      ExternalSecret references it only when `opsRoute.enabled`, so other envs are
      unaffected. **Do this before step (c)** — flipping the flag without the field
      makes ESO sync fail and CrashLoops the production Pomerium (which also serves the
      live kubectl gateway).

   b. **Public key → tuist-ops.** Paste the `pomerium_pub.pem` contents into
      `infra/helm/tuist-ops/values-managed-production.yaml` as `pomerium.publicKey`
      (audience defaults to `ops.tuist.dev`). The chart renders it to
      `POMERIUM_JWT_PUBLIC_KEY`; empty until now, so the surface was failing closed.

   c. **Flip the flags (one deploy).**
      - `infra/helm/pomerium/values-production.yaml`: `opsRoute: { enabled: true }` —
        adds the three `ops.tuist.dev` routes (`/grants` + `/audit` OIDC,
        `/webhooks/slack` public; `/api/v1/policy` stays tailnet-only) and the host on
        the Pomerium Ingress.
      - `infra/helm/tuist-ops/values-managed-production.yaml`: `ingress: { enabled: false }`
        — drops tuist-ops's own `ops.tuist.dev` Ingress so the two don't both claim the
        host. Slack webhooks keep working through Pomerium's public route.

   d. **DNS/cert converge.** On deploy, cert-manager extends the Pomerium cert to
      `ops.tuist.dev` (Cloudflare DNS-01) and external-dns repoints the A record at the
      Pomerium Ingress. Verify the reason form loads through Google OIDC and that a
      Slack JIT approval still round-trips before considering the cutover done. This is
      the one production-topology change to confirm before applying.

5. **Defence in depth — restrict the tailnet so only Pomerium reaches the ops surface.**
   The crypto check in (4) already blocks a raw-tailnet forger (no valid assertion),
   but the ops Service is `tailscale.com/expose: "true"` and `infra/tailscale/acls.json`
   still has the catch-all `{"src":["*"],"dst":["*"],"ip":["*"]}`, so any tailnet device
   can still *reach* it. Once that catch-all is removed (its own pending audit), give the
   ops app Service a dedicated tag (not the shared `tag:tuist-k8s-<env>`; the Tailscale
   OAuth client must be authorised to mint it) and add a grant restricting it to the
   Pomerium proxy + the kube-impersonator sidecar (for `/api/v1/policy`). Until then this
   is documentation, not enforcement.

6. **`return_to` allowlist.** Set `PROJECT_ACCESS_RETURN_TO_ALLOWLIST` on ops to the
   app origin(s) (defaults to `https://tuist.dev`) so a signed token can't be
   redirected to an attacker host.
