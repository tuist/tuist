defmodule Tuist.Sandboxes.Workers.ExpireSandboxesWorker do
  @moduledoc """
  Ends the sandboxes whose lifetime ran out (`Tuist.Sandboxes.expire_sandboxes/0`):
  pauses running ones and queues the archive of paused ones. Only sandboxes
  created through the account API, MCP or `tuist sandbox create` have a
  lifetime; integrations own the lifecycle of theirs.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [states: [:available, :scheduled, :executing], period: :infinity]

  alias Tuist.Sandboxes

  @impl Oban.Worker
  def perform(_job) do
    Sandboxes.expire_sandboxes()
    :ok
  end
end
