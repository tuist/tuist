# GitHub automation

Workflows live in `workflows/`, reusable actions in `actions/`, and supporting
scripts in `scripts/`. Changes to privileged workflows must keep contributor
content separate from executable code.

## Community notifications

`workflows/community-notifications.yml` sends new community issues and PRs to
Slack. Filtering and payload construction live in
`scripts/community-notifications.cjs`; setup and operational limitations are
documented in `COMMUNITY_NOTIFICATIONS.md`.

- Exclude `company` and `external` team members, GitHub bots, and explicitly
  listed legacy automation accounts. Do not use repository association as an
  employment signal.
- Membership lookup errors must fail visibly, not produce staff notifications.
- The privileged PR workflow must only check out trusted event code, never a
  PR head or merge ref. Keep contributor text in plain-text Slack blocks.
- Validate changes with `node --test scripts/community-notifications.test.cjs`
  from this directory and `actionlint workflows/community-notifications.yml`.

## Tuist Elixir package

`tuist-ex.yml` runs separate compilation, documentation, test, formatting,
and package jobs. Compilation covers the minimum and current supported Elixir
versions. The workflow is reused by `tuist-ex-release.yml` before publication.
Releases run only from `main`, serialize publishing, and use the shared
`release:check` registry with the `tuist-ex@` tag prefix. The existing
`HEX_API_KEY` secret used by Noora must be able to publish `tuist_ex`.
