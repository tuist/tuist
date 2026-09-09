# Activity log parser

- This Swift package builds a standalone executable, despite the historical `nif` directory name. Parser crashes must remain isolated from the BEAM.
- The executable receives five paths: activity log, CAS database, legacy CAS metadata directory, summary JSON, and step JSONL. Write each step through the parser callback, leaving `BuildData.build_steps` empty in the production summary. The default array result remains available to library callers and tests.
- `BuildStepLog` normalizes at most the retained prefix/suffix and caps each step independently at 64 KiB. Retain the end of oversized output for diagnostics; never introduce a shared budget that starves later steps.
- Elixir consumes the sidecar within the parser callback and cleans up both output files on success or failure. Coordinate protocol changes with `lib/tuist/processor/xcactivitylog_parser.ex`.
- Validate this standalone server package with `swift test --replace-scm-with-registry` and `swift build -c release --replace-scm-with-registry`. The CLI's Xcode-only workflow does not apply to this package.
