defmodule Tuist.Sandboxes.Workers.ReclaimCapacityWorker do
  @moduledoc "Reclaims idle memory asynchronously after a controller allocation or a pause."
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:node], states: [:available, :scheduled, :executing, :retryable], period: :infinity]

  alias Tuist.Sandboxes.Capacity

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"node" => node}}), do: Capacity.reconcile_allocation(node)
end
