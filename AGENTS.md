# Tuist

Monorepo for the Tuist CLI, services, companion apps, and infrastructure. Read the
nearest `AGENTS.md` before working in a subsystem. Paths below are repository-relative.

## Subsystems

| Directory | Scope |
| --- | --- |
| [.github/](.github/AGENTS.md) | Automation, actions, and community notifications |
| ci/ | Buildkite plugins and GitLab cache templates; read the component guide |
| [cli/](cli/AGENTS.md) | Swift CLI, project generation, caching, and server client |
| [server/](server/AGENTS.md) | Phoenix application, analytics, and native build/test processors |
| [codebase-search/](codebase-search/AGENTS.md) | Bounded hosted source-code search |
| [cache/](cache/AGENTS.md) | Cache service |
| [registry/](registry/AGENTS.md) | Stateless package registry read frontend |
| [kura/](kura/AGENTS.md) | Rust distributed cache mesh |
| [cas-plugin/](cas-plugin/AGENTS.md) | Xcode CAS plugin and per-machine proxy |
| [tuist_ex/](tuist_ex/AGENTS.md) | Elixir build and test instrumentation |
| [tuist_common/](tuist_common/AGENTS.md) | Shared Elixir utilities |
| [atlas/](atlas/AGENTS.md) | Internal operations app |
| [atlas-native/](atlas-native/AGENTS.md) | Once-based Rust, Android, and iOS Atlas clients |
| [gradle/](gradle/AGENTS.md) | Gradle plugin |
| [app/](app/AGENTS.md), [android/](android/AGENTS.md) | Companion apps |
| [noora/](noora/AGENTS.md) | Phoenix component library and Storybook |
| [slack/](slack/AGENTS.md) | Public Slack invitation app |
| [tuist-ops/](tuist-ops/AGENTS.md) | Internal operations and access approvals |
| [kube-impersonator/](kube-impersonator/AGENTS.md) | Kubernetes access policy sidecar |
| [infra/](infra/AGENTS.md) | Helm charts, controllers, clusters, and VM images |
| [search/](search/AGENTS.md) | Typesense and indexers |
| [status/](status/AGENTS.md) | Cloudflare status-page worker |
| [grafana-datasource/](grafana-datasource/AGENTS.md) | Go/React Grafana plugin |
| [handbook/](handbook/AGENTS.md) | Company handbook (VitePress) |
| [swifterpm/](swifterpm/AGENTS.md) | Swift package restoration and Bazel/Buck helpers |
| skills/ | Agent skills published to `tuist/agent-skills` |

## Guardrails

- Do not edit generated `CHANGELOG.md` files.
- Edit English source content only. Never edit translation `.po` files; the
  Glossia GitHub App owns them. Gettext `.pot` templates may be updated.
- Keep Swift project prefix mapping enabled. Resolve test fixtures and snapshots
  through `TuistTestSupport` and the runtime checkout (`TUIST_CONFIG_SRCROOT`), not
  compiler-remapped `#file` or `#filePath` paths.
- When changing stored customer data (schemas, relationships, object-storage
  layouts, collection, or retention), update `server/data-export.md`. See
  `server/AGENTS.md` for the required export documentation details.
- Before operating on shared infrastructure, read `infra/AGENTS.md`, including
  its human-only elevation rules.

## Commits and pull requests

Use conventional commits with the affected subsystem as scope, for example
`fix(cli): resolve cache artifact upload issue`. Established scopes are `app`,
`android`, `server`, `atlas`, `atlas-native`, `codebase-search`, `cache`, `registry`,
`slack`, `kura`, `cli`, `tuist-ex`, `noora`, `skills`, `search`, `status`,
`grafana-datasource`, `docs`, and `handbook`.

PR descriptions must explain what changed, why, the root cause for fixes, relevant
alternatives, user/developer impact, and validation actually run. Preserve the
reasoning, not just a file list.

For reviews, use the project-specific context in
[Tuist Elixir review](.blick/skills/tuist-elixir-review/SKILL.md) or
[Tuist Swift review](.blick/skills/tuist-swift-review/SKILL.md), as applicable.
Only report findings whose cited line appears in the diff.

## Maintaining guidance

Keep instructions at the narrowest scope that needs them; children inherit parent
rules. Add a nested `AGENTS.md` only for distinct commands, boundaries, or
non-obvious constraints. Do not repeat parent rules, inventory source files, or
record session history. Put architecture and operational procedures in existing
READMEs/runbooks and link to them. Update guidance when its instructions change,
not for every code edit. `CLAUDE.md` aliases should continue to point to `AGENTS.md`.
