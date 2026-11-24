defmodule LuftServer.Notifications.LiveActivityStartWorker do
  @moduledoc """
  Starts Luft's threads Live Activity on the device of one push-to-start token
  (`LuftServer.Notifications.LiveActivities.start/1`) when its sign-in has none. Jobs carry
  only the token's row ID; at most one is pending per token.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:starter_id], states: [:available, :scheduled, :retryable]]

  alias LuftServer.Notifications.LiveActivities

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"starter_id" => id}}) do
    case LiveActivities.start(id) do
      :ok -> :ok
      {:retry, reason} -> {:error, reason}
      {:cancel, reason} -> {:cancel, reason}
    end
  end
end
