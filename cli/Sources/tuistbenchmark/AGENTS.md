# tuistbenchmark (CLI Tooling)

This target provides benchmark tooling for CLI workflows.

## Responsibilities
- Run or orchestrate benchmark scenarios.
- Keep benchmarking logic isolated from production command paths.

## Boundaries
- Avoid introducing production command wiring here; keep that in `cli/Sources/TuistKit`.

## Related Context
- CLI entry point: `cli/Sources/tuist/AGENTS.md`
- Command wiring: `cli/Sources/TuistKit/AGENTS.md`
