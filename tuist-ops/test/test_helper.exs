alias Ecto.Adapters.SQL.Sandbox

# Mimic doubles for any module the bot calls through (Slack /
# Tailscale HTTP, env var reads). Mirrors server's test_helper
# shape so tests can stub via `stub(Module, :fun, fn ... -> ... end)`.
Mimic.copy(TuistOps.Environment)
Mimic.copy(TuistOps.GitHub.AppToken)
Mimic.copy(TuistOps.Previews)
Mimic.copy(TuistOps.Previews.GitHubActionsClient)
Mimic.copy(TuistOps.JIT.Approvals)
Mimic.copy(TuistOps.JIT.SlackClient)
Mimic.copy(TuistOps.JIT.TailscaleClient)
Mimic.copy(JOSE.JWK)
Mimic.copy(JOSE.JWT)
Mimic.copy(JOSE.JWS)
Mimic.copy(Req)

ExUnit.start(exclude: [:skip])
Sandbox.mode(TuistOps.Repo, :manual)
