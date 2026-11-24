# Revoking customer credentials after an incident

Use this when customer credentials may have leaked, for example through a
compromised CI provider or a database read. Revocation acts on each
credential (`Tuist.Accounts.CredentialRevocation`). Do not rotate the bcrypt
pepper (`SECRET_KEYS/password`) instead: it also invalidates every password
and Kura client secret, and forces every customer to reset them.

Revocation cannot be undone. Revoked users sign in again, and admins create
new tokens.

## What it revokes

For one account, or for every account:

- browser sessions and pending sign-in links, and connected dashboards;
- CLI and app refresh tokens, and device codes;
- OAuth grants and agent credentials;
- account tokens (including SCIM) and project tokens;
- every access JWT issued at or before the revocation, through
  `users.credentials_revoked_at` and `accounts.credentials_revoked_at`.

Revoking an organization also revokes the user credentials of its members,
which signs them out of their other accounts too.

Not covered:

- Cache JWTs: cache nodes verify them on their own until they expire, within
  30 minutes.
- The per-node authentication cache: a revoked credential can keep working on
  a node for up to a minute.
- Passwords, passkeys and MFA factors, which are not bearer credentials. If
  those leaked, handle them separately (password resets).

## 1. Get write access

Both tasks write to production, so they need canary/production write access
as described in [infra/AGENTS.md](../../infra/AGENTS.md#cluster-access-for-agents):
a person elevates themselves with `/elevate production <intent>` in Slack; an
Amp orb thread asks for a thread elevation through Atlas's
`request_cluster_elevation`, which the person approves. Name the account (or
"every account") and the tasks below in the intent.

## 2. Pick a server pod and the account

```sh
kubectl --context tuist-k8s-production -n tuist get pods -l app.kubernetes.io/component=server
POD=tuist-tuist-server-...

kubectl --context tuist-k8s-production -n tuist exec $POD -- \
  bin/tuist rpc 'IO.inspect(Tuist.Accounts.get_account_by_handle("<handle>").id)'
```

Run the tasks on a live server pod with `bin/tuist rpc`, not `bin/tuist eval`,
so connected dashboards are disconnected too.

## 3. Revoke

One account:

```sh
kubectl --context tuist-k8s-production -n tuist exec $POD -- \
  bin/tuist rpc 'IO.inspect(Tuist.Release.revoke_credentials(<account id>))'
```

It returns how many rows each step touched, such as
`%{users: 2, account_tokens: 1, project_tokens: 1}`.

Every account, which signs out every customer and every Tuist employee:

```sh
kubectl --context tuist-k8s-production -n tuist exec $POD -- \
  bin/tuist rpc 'IO.inspect(Tuist.Release.revoke_credentials(:everything))'
```

Each step is idempotent and they are not one transaction, so if a run is
interrupted, run it again.

## 4. Check it

Wait a minute for the per-node authentication caches, then:

- A token you know belonged to the account gets `401` from
  `https://tuist.dev/api/projects`.
- The server logs show no new errors, and the 401 rate rises only by the
  revoked account's traffic.

## 5. Tell the admins

```sh
kubectl --context tuist-k8s-production -n tuist exec $POD -- \
  bin/tuist rpc 'IO.inspect(Tuist.Release.send_credential_rotation_notice(<account id>, kind: :revoked, details_url: "https://..."))'
```

- `kind: :revoked` says Tuist revoked the credentials; use it after step 3.
  `kind: :rotate` asks admins to rotate them themselves, without a revocation.
- The scope is an account ID or `:everything`. Organization admins get one
  email each; a personal account's owner gets one.
- `details_url` links the incident write-up and is optional.
- It returns `%{notice_id: ..., queued: n}`. If the run is interrupted, run it
  again with `notice_id: "<id>"`; nobody is emailed twice.

The emails are sent by `Tuist.Accounts.Workers.CredentialRotationNoticeWorker`
jobs, which retry on failure. To check them:

```sh
kubectl --context tuist-k8s-production -n tuist exec $POD -- \
  bin/tuist rpc 'import Ecto.Query; IO.inspect(Tuist.Repo.all(from j in Oban.Job, where: j.worker == "Tuist.Accounts.Workers.CredentialRotationNoticeWorker" and fragment("?->>'"'"'notice_id'"'"'", j.args) == "<notice id>", group_by: j.state, select: {j.state, count(j.id)}))'
```

## Rehearsal

Rehearsed on staging on 2026-11-17 against two throwaway organizations, each
with one credential of every kind. Revoking one of them turned all seven of
its credentials (legacy user and project tokens, which no longer exist since
2026-11-19, project token, account token, account JWT, user JWT, CLI refresh
token) and its browser session from
accepted to `401` within the minute, left the other organization's working,
and let its users sign in again afterwards. The rotation notice reached the
one admin, and a rerun with its `notice_id` queued nothing. `:everything` was
not rehearsed, since it signs out every staging user.
