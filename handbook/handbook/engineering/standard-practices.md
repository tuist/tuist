---
{
  "title": "Standard practices",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "Standard practices are the set of guidelines that Tuist engineers follow to ensure that the codebase is consistent, maintainable, and scalable."
}
---
# Standard practices

## Trunk-based development

Tuist repositories follow [trunk-based development](<https://en.wikipedia.org/wiki/Branching_(version_control)>) with `main` as the default branch, requiring at least two approvals for pull requests and CI to pass before merging. CI checks should include thorough testing, linting, and code formatting that ensures code style consistency throughout the organization.
