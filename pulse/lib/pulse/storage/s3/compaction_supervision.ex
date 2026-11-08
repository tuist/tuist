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
      | config |> lanes() |> Enum.with_index() |> Enum.flat_map(&lane(config, &1))
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp lanes(config) do
    signals = CompactionOwnership.signals(config)

    metric_lanes =
      if "metrics" in signals and Map.get(config, :metric_finalize_enabled, true), do: ["metrics_grouping"], else: []

    trace_lanes = if "traces" in signals, do: ["traces_recent"], else: []
    signals ++ metric_lanes ++ trace_lanes
  end

  # Separate tasks and eligibility keep historical maintenance from delaying
  # recent metric grouping, recent trace compaction, or the other signals.
  # The first lane keeps the unsuffixed names.
  defp lane(config, {signal, index}) do
    {tasks, worker} =
      if index == 0,
        do: {CompactionTasks, CompactionWorker},
        else: {Module.concat(CompactionTasks, signal), Module.concat(CompactionWorker, signal)}

    {signal, operation} =
      case signal do
        "metrics_grouping" -> {"metrics", :metric_consolidate}
        "metrics" -> {"metrics", :metric_compact}
        "traces_recent" -> {"traces", :trace_recent}
        "traces" -> {"traces", :trace_compact}
        signal -> {signal, :compact}
      end

    config =
      Map.merge(config, %{
        maintenance_signal: signal,
        maintenance_operation: operation,
        compaction_tasks: tasks,
        worker_name: worker
      })

    [
      Elixir.Supervisor.child_spec({Task.Supervisor, name: tasks, max_children: 4}, id: tasks),
      Elixir.Supervisor.child_spec({CompactionWorker, config}, id: worker)
    ]
  end
end
