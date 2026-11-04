defmodule Tuist.RemoteExecution.MaintenanceWorker do
  @moduledoc false
  use Oban.Worker, queue: :remote_execution_maintenance, max_attempts: 3

  @impl Oban.Worker
  def perform(_job), do: Tuist.RemoteExecution.maintain()
end
