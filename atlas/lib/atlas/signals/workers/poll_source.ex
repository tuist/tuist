defmodule Atlas.Signals.Workers.PollSource do
  @moduledoc false
  use Oban.Worker,
    queue: :default,
    max_attempts: 4,
    tags: ["signals"],
    unique: [period: :infinity, states: :incomplete]

  alias Atlas.Signals.Polling

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => id}}), do: Polling.poll(id)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(3)
end
