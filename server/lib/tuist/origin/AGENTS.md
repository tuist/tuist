# Origin (Context)

Origin is a Git forge integration for native Cursor Origin repositories, not Cursor Cloud Agent compute or the MCP/plugin marketplace.

## Responsibilities
- `Tuist.Origin` persists account-owned installations and links projects only after account-update authorization, ownership checks, and a native-repository API probe. Installation details/repository discovery also reauthorize account updates and scope the local installation to the current account and deployment App ID before HTTP calls. Return only the namespace slug and sorted native repository choices to the UI; do not persist fetched installer profiles or repository lists.
- `Client` signs five-minute EdDSA app JWTs, mints short-lived least-privilege installation tokens, paginates installation repository discovery and comments, and creates/updates general PR discussions. Never automatically retry comment writes inside the HTTP client.
- `Signatures` validates Origin installation receipts and raw-body webhook signatures against Cursor's public JWKS, with issuer/audience/state/expiration checks and a five-minute webhook replay window. The app private key is not a webhook verification key.
- `WebhookWorker` durably accepts lifecycle notifications through Oban and reconciles against current API state so reordered or retried events cannot reinstate deleted installations. Token minting rechecks access for every operation; cached tokens and webhook snapshots are not authoritative.
- Shared report generation and provider dispatch live in `../vcs.ex`. Branch and PR refs resolve only to an unambiguous open PR with the current reported head SHA. Stale commits do not overwrite a newer PR report.

## Guardrails
- Deployment identity is `TUIST_ORIGIN_APP_ID` plus an independent environment's `TUIST_ORIGIN_APP_PRIVATE_KEY` Ed25519 PEM. Never persist app private keys in installation records or log receipts/tokens.
- Only the project's own, same-account installation may post. Origin and GitHub credentials must not cross forge boundaries, even for identical owner/repository handles.
- Request `repository:pull_requests:read` and `repository:pull_requests:reviews:write`. Origin implicitly grants the corresponding review-read permission. Metadata access is automatically approved during consent, but narrowed installation tokens must explicitly include `repository:metadata:read`; otherwise repository discovery succeeds while `GET /repos/{owner}/{repo}` returns 403. Keep the consent scopes separate from the installation-token scope list. A PR-read probe rejects mirrors without adding `repository:mirror:read`.
- Use native Origin repositories; GitHub mirrors continue through GitHub. Installation does not run CI or upload results. Checks, CI orchestration, code access, and user delegation are out of scope.
- Customer metadata is documented in `../../../data-export.md`. Browser consent and webhook handling belong in `../../tuist_web`.
