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
  environment and `exp - iat` is capped, so a compromised signer can't mint a
  long-lived or cross-env grant.
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

4. **Pomerium MUST front `ops.tuist.dev/grants/*`.** The reason form trusts
   `X-Pomerium-Claim-Email` as the operator identity. That header is only
   trustworthy if Pomerium (Google Workspace OIDC) sets it and strips any
   client-supplied copy. Until Pomerium fronts ops.tuist.dev (PR #10988 deferred
   this; the public ingress currently routes only `/webhooks/slack/*`), the
   `/grants/*` routes MUST NOT be exposed on the unprotected public ingress — a
   spoofed header would let anyone mint a grant for any operator email. Add
   `/grants/*` to the Pomerium-protected route set, not the raw ingress.

5. **`return_to` allowlist.** Set `PROJECT_ACCESS_RETURN_TO_ALLOWLIST` on ops to the
   app origin(s) (defaults to `https://tuist.dev`) so a signed token can't be
   redirected to an attacker host.
