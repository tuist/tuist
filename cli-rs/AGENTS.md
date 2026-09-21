# cli-rs (incurs front end over the Swift CLI)

A Rust `tuist` binary built on incurs. It links the real Swift CLI through the
`TuistEmbed` dynamic library and adds incurs surfaces (`--llms`, `--mcp`, skills,
completions) without rewriting any Swift logic.

## How it fits together
- `spec/tuist.spec.json` is the Swift CLI's `--experimental-dump-help` output. `src/spec.rs`
  turns it into an incurs tree where every command is a raw command, so Swift keeps parsing
  arguments, printing help, and choosing exit codes. A raw root receives everything the tree
  cannot run (plugin tasks, unknown commands, `--help`).
- `src/swift.rs` runs a command in-process through `tuist_run` from a terminal. Under
  `tuist --mcp` it runs each command in a child copy of this binary and returns its output,
  because the Swift CLI sets up process-wide state once (`tuist_run` refuses a second call).
- The Swift side lives in `cli/Sources/TuistEmbed` and `cli/Sources/TuistCLICore`
  (`TuistCommand.isEmbedded` makes exits throw `EmbeddedExit`).

## Invariants
- The binary must sit next to `libTuistEmbed.dylib`, ProjectDescription, and the resource
  bundles, the same layout as the Swift `tuist`; resources are found relative to it.
- Output, help text, and exit codes must match the Swift `tuist` for the same argv.
- Regenerate the spec whenever commands change: `cli-rs/scripts/update-spec.sh <swift tuist>`.

## Checks
- `cli-rs/scripts/ci.sh` runs everything the `cli-rs` workflow runs. The pieces:
- `swift build --replace-scm-with-registry --product TuistEmbed` and `--product tuist`, then
  `cli-rs/scripts/install-project-description.sh` (a manifest-compilable ProjectDescription for
  SwiftPM builds) and `cli-rs/scripts/dev-install.sh` (replaces the binary rather than
  overwriting it; macOS kills a signed binary rewritten in place).
- `cd cli-rs && cargo test`
- `cli-rs/scripts/parity.sh .build/debug` compares both binaries command by command.
- `cli-rs/scripts/mcp_smoke.py .build/debug/tuist-rs <project dir>` calls commands over MCP.
- `cli-rs/scripts/update-spec.sh .build/debug/tuist --check` fails on a stale spec.
