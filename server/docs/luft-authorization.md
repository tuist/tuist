# Luft upstream authorization

The configured confidential Luft server client can request:

```text
openid profile email account:organizations:write luft:app mcp account:delete account:members:read account:sandboxes:write account:repositories:read account:repositories:write project:admin:read project:previews:read project:previews:write
```

`Tuist.OAuth.Clients.luft_server_scopes/0` defines this allowlist. Luft server
must request the scopes when authorizing a user; existing grants do not gain
them. Keep the Tuist refresh/access tokens on Luft server and forward the Tuist
access token to Tuist when proxying a user request.

Every authorization by this client requires explicit, CSRF-protected consent
on Tuist, including when the person already has a Tuist browser session. Its
confidential upstream identity does not prove who controls the downstream
native callback. Omitting `prompt=consent` cannot bypass approval, and a previous
approval is not remembered. Cancelling issues no authorization code.

| Scope | Permission path |
| --- | --- |
| `openid profile email` | OpenID Connect identity and userinfo. |
| `account:organizations:write` | Organization creation through `OrganizationsController.oauth_organization_creator/1`. |
| `account:delete` | `DELETE /api/accounts/:handle` through `AccountController.oauth_account_deleter/1`, restricted to the configured Luft client and an active OAuth grant. The existing `account_delete` authorization still requires account administrator permission. `luft:app` alone does not permit deletion. |
| `luft:app` | `Authentication.app_user/1` admits the configured client's active grant to feature flags, AI subscriptions, generic inference/MCP transport and the account-context projection. Current user activity, Luft flags and membership are rechecked. Threads, lounges, runners and their sockets live in Luft, not Tuist. |
| `luft:app` | `Push.oauth_session/3` admits the grant as `app: "luft"` only where the endpoint allows Luft: generic push-device/ActivityKit token transport and telemetry. `POST /api/me/luft-notifications` dispatches only to the exact authenticated user's owning grant. Luft owns notification projections and scheduling. Tuist-only notification rules stay closed. |
| `mcp` | Read-only built-in tool discovery/calls through Tuist's existing `/mcp` endpoint. Personal MCP credentials remain in Tuist behind its scoped transport API. |
| `account:sandboxes:write` | Workspace allocation, execution and command capabilities under `/api/accounts/:handle/workspace-capabilities`, checked against current account administration and sandbox feature access. No infrastructure credentials leave Tuist. |
| `account:repositories:read` / `account:repositories:write` | Repository catalog, authorization, checkout/review, and explicit reviewed publication through the same capability endpoint. Publication has a durable account-owned replay ledger; reconciliation observes and never retries a GitHub write. |
| `account:members:read` | Organization detail through `Authorization`'s `organization_read`, including its account/issuer membership check. Organization listing uses the OAuth user and needs no extra scope. |
| `project:admin:read` | Project detail through `project_read`, within the issuer's accessible projects. |
| `project:previews:read` | Preview list, tracks and detail through `preview_read`. |
| `project:previews:write` | Preview deletion through `preview_delete`. This existing scope also permits preview publication; Tuist has no deletion-only preview scope. It includes preview reads. |

`luft:app` grants no project, preview or account administration permission by
itself. The configured client remains confidential and scoped;
`Push.first_party_session?/2` still recognizes only the existing native clients.
Other confidential clients cannot use `luft:app` to enter these app paths.
Native Luft and the shipping Tuist app retain their existing authorization.

Push installations retain their current grant-lineage binding. Delivery checks
the configured client, user, refresh-token lifetime and `luft:app` on the active
descendant grant. Refresh rotation preserves delivery; revocation, refresh
expiry or downscoping ends it. Tuist uses the existing Luft app/platform and
APNs routing, with no storage changes.

Brokered notification links, Live Activity links and push-to-start server
attributes use the Luft base URL derived from the root grant's registered
`/auth/callback` URI, including custom ports and deployment prefixes. The
callback must still be registered for the configured Luft client. Destinations
never come from device parameters or refreshed-token redirects. Direct native
sign-ins retain the Tuist origin; no new origin column is stored.

Conversation sockets terminate at Luft and use only Luft's bearer WebSocket
subprotocol, not a URL parameter or an upstream Tuist token. Luft reloads account
context for thread and presence permissions. Local runner poll/result endpoints
require Luft's session-bound machine credential, not this user grant. Tuist no
longer exposes conversation or runner routes or sockets.

There is no `GET /api/accounts/:handle` detail endpoint. Organization details
use `GET /api/organizations/:handle`; project details use
`GET /api/projects/:account/:project`. Account renaming and organization
administration retain their existing authorization; `luft:app` does not add
OAuth authorization to those endpoints. Account deletion requires the separate
`account:delete` scope above.

Regression coverage lives in
`test/tuist_web/controllers/oauth/openid_provider_test.exs`, alongside the native
push and capability suites. Local conversation/runner/channel regression coverage
lives under `luft-server/test/`.
