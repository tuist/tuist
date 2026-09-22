defmodule Atlas.MCP.Workers.RefreshOAuthSessions do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.MCP

  # Expired grants authorize nothing — they are never forwarded — but they are
  # encrypted bearers and should not sit in the table indefinitely. This job
  # already runs on the cadence MCP session hygiene needs.
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    MCP.prune_expired_operator_grants()
    MCP.prune_expired_grant_requests()
    MCP.refresh_expiring_oauth_sessions()
  end
end
