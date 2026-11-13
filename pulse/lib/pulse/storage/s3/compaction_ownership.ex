defmodule Pulse.Storage.S3.CompactionOwnership do
  @moduledoc """
  Expected compaction owners among live workers, scoped to a store and signal.
  Membership is an optimization; conditional object publication fences races.
  """
  alias Pulse.Rendezvous
  alias Pulse.Runtime.ProcessGroup

  @scope __MODULE__

  def scope, do: @scope
  def group(config), do: {__MODULE__, config[:endpoint], config[:region], config[:bucket]}
  def group(%{maintenance_operation: :metric_consolidate} = config, "metrics"), do: {group(config), :metric_consolidate}
  def group(%{maintenance_operation: :trace_recent} = config, "traces"), do: {group(config), :trace_recent}

  def group(config, "metrics"), do: group(config)
  def group(config, "traces"), do: {group(config), :traces}
  def group(config, "logs"), do: {group(config), :logs}

  # A maintenance lane (`CompactionSupervision`) owns only its own signal.
  def signals(%{maintenance_signal: signal}), do: [signal]

  def signals(config) do
    metric_default = not Map.has_key?(config, :trace_compaction_enabled)

    Enum.filter(["metrics", "logs", "traces"], fn
      "metrics" -> Map.get(config, :compaction_enabled, metric_default)
      "logs" -> log_maintenance_enabled?(config)
      "traces" -> trace_maintenance_enabled?(config)
    end)
  end

  def trace_maintenance_enabled?(config), do: Map.get(config, :trace_compaction_enabled, false)
  def log_maintenance_enabled?(config), do: Map.get(config, :log_compaction_enabled, false)

  def join(config) do
    Enum.each(signals(config), &ProcessGroup.join(@scope, group(config, &1), self()))
    :ok
  end

  def leave(config) do
    Enum.each(signals(config), &ProcessGroup.leave(@scope, group(config, &1), self()))
    :ok
  end

  def join_once(config) do
    Enum.each(signals(config), fn signal ->
      if self() not in ProcessGroup.get_local_members(@scope, group(config, signal)),
        do: ProcessGroup.join(@scope, group(config, signal), self())
    end)

    :ok
  end

  def members(config), do: members(config, "metrics")

  def members(config, signal) do
    @scope
    |> ProcessGroup.get_members(group(config, signal))
    |> Enum.map(&node/1)
    |> Enum.uniq()
  end

  def owner(tenant, signal, members), do: Rendezvous.owner(["compaction", tenant, signal], members)
  def local_owner?(tenant, signal, config), do: owner(tenant, signal, members(config, signal)) == node()
end
