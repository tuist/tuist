# OIDC (Context)

This context verifies CI provider OIDC tokens and decides which write scopes an exchanged Tuist token carries.

## Responsibilities
- Verify GitHub Actions, CircleCI, and Bitrise OIDC tokens and extract the repository and workflow claims (`Tuist.OIDC`).
- Store and evaluate per-project and per-account scope rules on `ref`, `job_workflow_ref`, and `environment` (`Tuist.OIDC.ScopeRules`). Non-matching write scopes are recorded in the token's `withheld_scopes` claim and enforced by `Tuist.Authorization.Checks.scopes_permit/3`, which substitutes the matching read scope.
- Record which providers exchange tokens for each project (`Tuist.OIDC.ProjectProviders`) so the settings UI can warn when rules would affect CircleCI or Bitrise runs.

## Boundaries
- The token exchange endpoint lives in `server/lib/tuist_web/controllers/api/oidc_controller.ex`; the rules UI lives in `server/lib/tuist_web/live/project_oidc_settings_live.ex` and the account Cache page.
- Anything that authorizes writes for an `AuthenticatedAccount` must go through `Tuist.Authorization` so withheld scopes apply; cached decisions must be keyed by the token's permissions.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Only GitHub Actions claims are mapped; tokens from other providers fail any configured rule.
- Rules and provider records are customer data; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Authorization: `server/lib/tuist/authorization/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
