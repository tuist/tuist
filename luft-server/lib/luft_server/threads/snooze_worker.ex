defmodule LuftServer.Threads.SnoozeWorker do
  @moduledoc "Wakes only the exact timed snooze that scheduled this durable job."
  use Oban.Worker, queue: :threads, max_attempts: 3

  alias LuftServer.Threads

  def schedule!(%{id: id, snoozed_until: %DateTime{} = until}) do
    %{"thread_id" => id, "until" => DateTime.to_iso8601(until)}
    |> new(scheduled_at: until)
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => id, "until" => value}}) do
    with {:ok, until, 0} <- DateTime.from_iso8601(value),
         {:ok, _} <- Threads.wake_snoozed(id, until) do
      :ok
    end
  end
end
