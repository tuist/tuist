# Sandbox commands

`tuist sandbox` manages an account's sandboxes through the sandbox API.

- Keep list, show, analytics, pause, resume, archive and delete aligned with the
  public API and MCP contract in `server/lib/tuist/sandboxes/query.ex` and
  `schemas.ex`; create and exec use the API only (MCP omits them). Change server
  schemas and regenerate OpenAPI; never edit generated files.
- The server enforces roles (members reach their own build sandboxes, admins
  everything); the CLI does not check them. `--account` overrides the project
  full-handle account.
- `exec` joins the arguments after `--` with spaces and the server runs them with
  `bash -l`; it streams stdout and stderr and exits with the command's exit status
  (`ExitCode`), without an error message. `--json` buffers the output and prints
  `status`, `exit_code`, `stdout` and `stderr` once. Pausing a sandbox that is
  already paused succeeds. Deleting requires `--yes`.
- An error status whose body is not the server's `{"message": …}`, such as a
  proxy's error page, reports the status, not the generated client's decoding error.
- Show the dashboard `status` and fall back to `state` for servers that do not
  send it. `status` and `bucket` are open strings: never switch on them exhaustively.
- Test through the generated Xcode workspace and Swift Testing, not SwiftPM.
- `exec`, `sync` and `cp` go through the commands API (`SandboxRemote`):
  a command starts detached and its ND-JSON log stream resumes from the last
  byte offsets after a drop, a 5xx or a mid-stream `error` line, giving up after
  15 minutes without progress; a 404 ends it at once. Starting a command and
  stdin writes wait through 503s while CI holds a shared macOS host. `exec` exits
  with the command's status (124 on timeout, 130 when cancelled) and cancels it
  on SIGINT/SIGTERM. Progress notes go to stderr, never stdout. The synchronous
  `POST .../exec` endpoint stays in the API; the CLI no longer uses it.
- `cp` takes `<sandbox-id>:<path>` on exactly one side (only a UUID before the
  colon counts) and follows `cp -r`: into an existing directory or one written
  with a trailing `/` (created), otherwise to that path, replacing it. Both directions move a gzipped tar with
  `COPYFILE_DISABLE=1` and place it with a rename from a scratch directory next
  to the destination.
- `sync` (`SandboxSync`) mirrors the worktree's non-ignored files one way, file
  by file, like Amp's Mac satellites; the sandbox needs no Git or repository
  access. Git only lists and hashes files locally, through a scratch index under
  `<git-dir>/tuist-sync` so the user's staging area is untouched. Each sync's
  manifest is saved there by its hash, and the sandbox records the hash it holds
  under `$HOME/.tuist-sync/`, so the next sync uploads only files whose content
  or mode changed, plus the paths that left. Ignored files the sandbox created
  stay. When the sandbox's hash is unknown locally, changes mid-sync, or its
  copy lost files it was sent (such as a deleted copy), everything is sent with
  the full path list. One stdin-attached command probes
  and applies, so the sandbox cannot pause between them; a bundle over one
  stdin write goes through a presigned upload (`POST .../uploads`), and stdin
  remains the fallback for servers without it.
