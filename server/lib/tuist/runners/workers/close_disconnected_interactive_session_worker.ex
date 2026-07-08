defmodule Tuist.Runners.Workers.CloseDisconnectedInteractiveSessionWorker do
  @moduledoc """
  Closes an interactive session after its browser WebSocket disconnects
  and no newer connection has taken over during the grace period.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Runners.InteractiveSessions

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id, "connection_id" => connection_id}}) do
    case InteractiveSessions.close_if_disconnected(session_id, connection_id) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.warning("runners: failed to close disconnected interactive session",
          session_id: session_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
