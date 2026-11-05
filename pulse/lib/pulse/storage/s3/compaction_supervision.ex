defmodule Pulse.Storage.S3.CompactionSupervision do
  @moduledoc """
  Restarts the worker when its process-group scope restarts, restoring eligibility.
  """
  use Pulse.Runtime.Supervision

  alias Pulse.Runtime.Supervision, as: Supervisor
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3.CompactionOwnership
  alias Pulse.Storage.S3.CompactionTasks
  alias Pulse.Storage.S3.CompactionWorker

  def start_link(config), do: Supervisor.start_link(__MODULE__, config, name: __MODULE__)

  @impl true
  def init(config) do
    children = [
      %{id: CompactionOwnership, start: {:pg, :start_link, [CompactionOwnership.scope()]}}
      | config |> CompactionOwnership.signals() |> Enum.with_index() |> Enum.flat_map(&lane(config, &1))
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  # One worker and task supervisor per signal, so an hour's metric
  # finalization never delays log rollups or compaction of the other signals.
  # The first lane keeps the unsuffixed names.
  defp lane(config, {signal, index}) do
    {tasks, worker} =
      if index == 0,
        do: {CompactionTasks, CompactionWorker},
        else: {Module.concat(CompactionTasks, signal), Module.concat(CompactionWorker, signal)}

    config = Map.merge(config, %{maintenance_signal: signal, compaction_tasks: tasks, worker_name: worker})

    [
      Elixir.Supervisor.child_spec({Task.Supervisor, name: tasks, max_children: 4}, id: tasks),
      Elixir.Supervisor.child_spec({CompactionWorker, config}, id: worker)
    ]
  end
end
