defmodule Tuist.Sandboxes.Workers.ShrinkCarveOutsWorker do
  @moduledoc """
  Shrinks elastic sandbox carve-outs back toward what their running
  sandboxes hold, so memory sandboxes grew into goes back to the runner
  pools once they pause, and moves daemons' CPU requests to their
  sandboxes' guarantee. See `Tuist.Sandboxes.Capacity.shrink_carve_outs/0`
  and `Tuist.Sandboxes.Capacity.sync_cpus/0`.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 50]

  alias Tuist.Sandboxes.Capacity

  @impl Oban.Worker
  def perform(_job) do
    Capacity.shrink_carve_outs()
    Capacity.sync_cpus()
    :ok
  end
end
