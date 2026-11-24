defmodule Tuist.Runners.Workers.ConcurrencySizingWorker do
  @moduledoc """
  Grows paid accounts' runner concurrency from recurring usage and recent
  queue pressure. Sizing failures retry through Oban; no claim bypass exists.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :args], period: :infinity, states: :incomplete]

  alias Tuist.Runners.ConcurrencySizing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mode" => "daily"}}), do: ConcurrencySizing.sweep(:daily)
  def perform(%Oban.Job{}), do: ConcurrencySizing.sweep(:queue)
end
