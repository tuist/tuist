defmodule Tuist.Sandboxes.Workers.EndLeaseWorker do
  @moduledoc """
  Ends a macOS sandbox's session lease (`Tuist.Sandboxes.Commands.end_lease/1`)
  once the sandbox has been idle for the lease's length. At most one is
  pending per sandbox; each command that ends moves it later.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:sandbox_id], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Sandboxes.Commands

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => sandbox_id}}), do: Commands.end_lease(sandbox_id)
end
