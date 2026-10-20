defmodule Atlas.MCP.Workers.RefreshOAuthSessions do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.MCP

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    MCP.refresh_expiring_oauth_sessions()
  end
end
