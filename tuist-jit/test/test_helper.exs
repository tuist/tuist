alias Ecto.Adapters.SQL.Sandbox

# Mimic doubles for any module the bot calls through (Slack /
# Tailscale HTTP, env var reads). Mirrors server's test_helper
# shape so tests can stub via `stub(Module, :fun, fn ... -> ... end)`.
Mimic.copy(TuistJit.Environment)
Mimic.copy(TuistJit.SlackClient)
Mimic.copy(TuistJit.TailscaleClient)
Mimic.copy(Req)

ExUnit.start(exclude: [:skip])
Sandbox.mode(TuistJit.Repo, :manual)
