---
{
  "title": "Standard practices",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "How Tuist engineers land changes on main: trunk-based development, the same checks before and after merge, and optional peer review."
}
---
# Standard practices

## Trunk-based development

Tuist repositories follow [trunk-based development](<https://en.wikipedia.org/wiki/Branching_(version_control)>) with `main` as the production branch. Engineers may push or merge changes directly to `main`. Opening a pull request and obtaining peer review before merge is optional, not required. Only people with write access to the repository may push to `main`.

Development takes place in a controlled development environment. The same deterministic checks used in continuous integration, including tests and linting, are also run in that environment before a change is merged. Validating a change there is therefore equivalent to running those CI checks in a controlled environment. After the change is pushed to `main`, the same checks run again in GitHub Actions, so the controls run both before and after the merge. The repository provides shared mise tasks for these checks, which engineers can run locally and which CI also uses.

Automated continuous integration is the primary automated pre-production control after a change lands on `main`. GitHub Actions workflows run on every push to `main` and on pull requests. These workflows include unit and integration tests, linting and formatting checks, dependency and container vulnerability scanning (Trivy), and CodeQL analysis. Required status checks are not configured as a merge gate on `main`. Failed checks remain visible in GitHub Actions and shall be investigated and remediated.

Engineers use AI coding agents locally to review changes against repository guidelines before merging. Those guidelines are documented in `AGENTS.md` throughout the repository (with `CLAUDE.md` pointing to the same instructions), including project-specific review skills for Swift and Elixir. Automated agent review also runs on pull requests: GitHub Copilot code review is enabled on the repository, and CodeRabbit is configured to review pull requests.

Changes to `main` are traceable through git history and CI results. Failed CI checks on `main` are investigated and remediated. Peer review is not a required control.

Production software is deployed through documented GitHub Actions workflows. Changes to the hosted server are deployed from `main` first to a canary environment, then through acceptance checks, and then to production. Failed Helm releases are configured to roll back automatically. A previous known-good image or chart revision can be redeployed through the Server Deployment workflow. Production systems emit application and infrastructure metrics and error events. Application errors are sent to Tuist's self-hosted Atlas and Pulse error ingest. Kubernetes and application metrics are collected by the Kubernetes monitoring chart and evaluated as Grafana-managed alert rules, which route through Grafana IRM to Slack and the public status page.

These controls are also stated in the [Secure development policy](/security/secure-development-and-operations/secure-development-policy) and the [Operations security policy](/security/secure-development-and-operations/operations-security-policy).
