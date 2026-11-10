defmodule Atlas.Push.Workers.UpdateLiveActivity do
  @moduledoc false
  use Oban.Worker,
    queue: :push,
    max_attempts: 5,
    unique: [keys: [:registration_id], period: 60, states: :incomplete]

  alias Atlas.Push.OrbitLiveActivity

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"registration_id" => id}, attempt: attempt, max_attempts: max}) do
    OrbitLiveActivity.deliver(id, attempt >= max)
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(trunc(:math.pow(2, attempt)), 60)
end
