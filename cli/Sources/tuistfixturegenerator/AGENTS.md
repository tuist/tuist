# tuistfixturegenerator (CLI Tooling)

This target provides fixture generation tooling for tests and examples.

## Responsibilities
- Generate fixtures used by tests and sample projects.
- Keep fixture generation logic isolated from production command paths.

## Boundaries
- Avoid introducing production command wiring here; keep that in `cli/Sources/TuistKit`.

## Related Context
- CLI entry point: `cli/Sources/tuist/AGENTS.md`
- Command wiring: `cli/Sources/TuistKit/AGENTS.md`
