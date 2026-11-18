defmodule Tuist.Push.Workers.LiveActivityWorker do
  @moduledoc """
  Pushes one Tuist Guild Live Activity registration its current document
  (`Tuist.Push.LiveActivities.deliver/1`) and, while threads are working,
  schedules the next heartbeat. Jobs carry only the registration ID; at most one
  is pending per registration, and thread changes pull it forward.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:registration_id], states: [:available, :scheduled, :retryable]]

  alias Tuist.Push.LiveActivities

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"registration_id" => id}}) do
    case LiveActivities.deliver(id) do
      :continue -> LiveActivities.schedule_heartbeat(id)
      :done -> :ok
      {:snooze, seconds} -> {:snooze, seconds}
      {:retry, reason} -> {:error, reason}
      {:cancel, reason} -> {:cancel, reason}
    end
  end
end
