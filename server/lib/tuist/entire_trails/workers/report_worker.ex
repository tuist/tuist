defmodule Tuist.EntireTrails.Workers.ReportWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :vcs_comments,
    max_attempts: 10,
    replace: [scheduled: [:scheduled_at]],
    unique: [keys: [:connection_id], states: [:scheduled], period: :infinity]

  alias Tuist.EntireTrails

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connection_id" => connection_id}}) do
    EntireTrails.sync(connection_id)
  end
end
