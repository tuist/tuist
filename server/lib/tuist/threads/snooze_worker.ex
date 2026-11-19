defmodule Tuist.Threads.SnoozeWorker do
  @moduledoc """
  Ends a thread's timed snooze when it lasts no longer, and reminds the owner
  on their Luft devices (`Tuist.Threads.wake_snoozed/2`). Scheduled by
  `Tuist.Threads.snooze/4` for the snooze's `until`; a job for a snooze the
  owner has since changed or woken finds a different `until` and does nothing.
  """
  use Oban.Worker, queue: :threads, max_attempts: 3

  alias Tuist.Threads

  def schedule!(%{id: id, snoozed_until: %DateTime{} = until}) do
    %{"thread_id" => id, "until" => DateTime.to_iso8601(until)}
    |> new(scheduled_at: until)
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => thread_id, "until" => until}}) do
    {:ok, until, 0} = DateTime.from_iso8601(until)
    {:ok, _} = Threads.wake_snoozed(thread_id, until)
    :ok
  end
end
