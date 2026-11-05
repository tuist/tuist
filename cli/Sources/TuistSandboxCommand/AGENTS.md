# Sandbox commands

`tuist sandbox` manages an account's sandboxes through the sandbox API.

- Keep list, show, analytics, pause, resume, archive and delete aligned with the
  public API and MCP contract in `server/lib/tuist/sandboxes/query.ex` and
  `schemas.ex`; create and exec use the API only (MCP omits them). Change server
  schemas and regenerate OpenAPI; never edit generated files.
- Every request needs an account administrator; the server enforces it, the CLI
  does not check roles. `--account` overrides the project full-handle account.
- `exec` joins the arguments after `--` with spaces and the server runs them with
  `/bin/bash -lc`; it prints the streams and exits with the command's exit status
  (`ExitCode`), without an error message. Pausing a sandbox that is already paused
  succeeds. Deleting requires `--yes`.
- An error status whose body is not the server's `{"message": …}`, such as a
  proxy's error page, reports the status, not the generated client's decoding error.
- Show the dashboard `status` and fall back to `state` for servers that do not
  send it. `status` and `bucket` are open strings: never switch on them exhaustively.
- Test through the generated Xcode workspace and Swift Testing, not SwiftPM.
