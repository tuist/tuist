defmodule Tuist.Runners.Workers.PrepaidUsageWorker do
  @moduledoc "Bounded prepaid-pool scan and isolated per-activation usage evaluation."
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Runners.PrepaidNotifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activation_id" => id}}) do
    case PrepaidNotifications.enqueue(id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}), do: PrepaidNotifications.scan(Map.get(args, "after_id", 0))
end
