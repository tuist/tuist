# Flaky Fix Runner

A dedicated Elixir/Phoenix application that runs on the macOS machine and accepts webhook jobs from the main Tuist server.

## Responsibilities

- Accept signed flaky-fix webhook jobs from `server/`
- Maintain local GitHub checkouts for target repositories
- Run OpenCode with the flaky-test skill and local CLI tools
- Push fix branches and open draft PRs with `gh`
- Send status callbacks back to the main server

## Development

```bash
cd flaky_fix_runner
mix deps.get
mix phx.server
```

## Notes

- This service is intentionally hackday-grade and optimized for the happy path.
- It depends on `opencode`, `gh`, `git`, and `tuist` being installed on the machine.
