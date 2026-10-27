# Atlas Rust CLI

The `atlas` executable is the terminal surface of the same shared Rust catalog
used by Android and iOS. It currently supports `sections`, `url <section>` and
help. It does not fetch Atlas data, store credentials, or open a browser.

- Import the core's public catalog rather than copying section IDs, labels or
  destinations. Preserve the existing C and JNI interfaces when extending the
  core's Rust API.
- `sections` emits tab-separated ID, title and URL; `url` emits only the URL and
  one newline so callers can use it in shell scripts.
- Invalid arguments return exit code 2 with an actionable stderr message and no
  stdout. Output failures return exit code 1, except a closed stdout pipe, which
  ends successfully. Do not log or print errors into successful output streams.
- Keep parsing/rendering in `src/command.rs` and process/exit handling in
  `src/main.rs`. Tests live beside the command implementation.
- Build and test with `ONCE_CACHE_PROVIDER=local mise run build:cli` and
  `ONCE_CACHE_PROVIDER=local mise run test:cli` from `atlas-native/`. Do not
  switch native builds or tests to Cargo; the Cargo workspace is for Clippy and
  editor tooling.
- Invoke the built executable at `.once/out/AtlasCLI/atlas`. `once run AtlasCLI --
  <arguments>` is also available, but Once captures its stdout in the run's
  output log rather than printing it directly.
