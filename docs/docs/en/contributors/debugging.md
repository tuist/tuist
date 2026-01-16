---
{
  "title": "Debugging",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Use coding agents and local runs to debug issues in Tuist."
}
---
# Debugging {#debugging}

Being open is a practical advantage: the code is available, you can run it locally, and you can use coding agents to answer questions faster and debug potential bugs in the codebase.

## Use coding agents {#use-coding-agents}

Coding agents are useful for:

- Scanning the codebase for where a behavior is implemented.
- Reproducing issues locally and iterating quickly.
- Tracing how inputs flow through Tuist to find the root cause.

Share the smallest reproduction you can, and point the agent at the specific component (CLI, server, cache, docs, or handbook). The more focused the scope, the faster and more accurate the debugging process is.

### Frequently Needed Prompts (FNP) {#frequently-needed-prompts}

#### Unexpected project generation {#unexpected-project-generation}

The project generation is giving me something I do not expect. Run the Tuist CLI against my project at `/path/to/project` to understand why this is happening. Trace the generator pipeline and point to the code paths responsible for the output.

#### Reproducible bug in generated projects {#reproducible-bug-in-generated-projects}

This looks like a bug in generated projects. Create a reproducible project under `examples/`, using existing examples as a reference. Add an acceptance test that fails, run it via `xcodebuild` with only that test selected, fix the issue, re-run the test to confirm it passes, and open a PR.
