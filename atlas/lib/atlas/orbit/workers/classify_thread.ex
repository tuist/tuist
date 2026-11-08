defmodule Atlas.Orbit.Workers.ClassifyThread do
  @moduledoc "Classifies nonempty conversations and backfilled histories without delaying messages or replies."
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:thread_id], period: :infinity, states: :incomplete]

  alias Atlas.Orbit.Classification

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => thread_id, "message_id" => message_id, "user_id" => user_id}}) do
    Classification.classify(thread_id, message_id, user_id)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
