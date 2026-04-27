Review the diff against the elixir-code-review checklist, focusing on
correctness, OTP soundness (GenServer/Supervisor usage, blocking calls,
restart strategies), pattern matching, Ecto query safety, and security
items (atom exhaustion, eval, unsafe `binary_to_term`).

Repository-specific overrides — these take precedence over the skill:

- Do NOT flag missing `@spec`, `@type`, or `@typep`. This codebase
  intentionally avoids typespecs (see CLAUDE.md). Skip any "add a spec"
  finding.
- Do not flag missing `@doc` on internal helper modules; only flag it on
  modules that are clearly part of a public boundary (controllers,
  contexts, public API modules).
- Skip pure formatting/style nits — `mix format` and `mix credo` cover
  those in CI.

Be specific: cite the file and line, explain why it matters, and propose
a concrete fix when you can.
