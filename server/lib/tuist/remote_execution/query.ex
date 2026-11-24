defmodule Tuist.RemoteExecution.Query do
  @moduledoc """
  A project's remote execution activity and usage as the REST API and MCP
  tools return them (`Tuist.RemoteExecution.Schemas`). Callers authorize
  build reads on the project first.
  """
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.Usage

  @default_days 30
  @max_days 366

  def activity(project) do
    with {:ok, activity} <- RemoteExecution.activity(project) do
      {:ok,
       %{
         observed_at: iso8601(activity.observed_at),
         running: activity.running,
         queued: activity.queued,
         actions:
           Enum.map(activity.actions, fn action ->
             action
             |> Map.take([:state, :action_digest, :invocation_id, :mnemonic, :target, :vcpus, :memory_gb])
             |> Map.put(:since, iso8601(action.since))
           end),
         invocations: Enum.map(activity.invocations, &Map.put(&1, :started_at, iso8601(&1.started_at)))
       }}
    end
  end

  @doc """
  Usage over `[from, to)`, given as ISO 8601 strings or `DateTime`s. The
  period defaults to the last #{@default_days} days and spans at most
  #{@max_days} days.
  """
  def usage(project, args) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    with {:ok, to} <- datetime(arg(args, :to), now),
         {:ok, from} <- datetime(arg(args, :from), DateTime.add(to, -@default_days, :day)),
         true <- DateTime.before?(from, to) and DateTime.diff(to, from, :day) <= @max_days do
      usage = Usage.project_usage(project, from, to)

      {:ok,
       %{
         from: iso8601(from),
         to: iso8601(to),
         granularity: Atom.to_string(usage.granularity),
         executions: usage.executions,
         execution_ms: usage.execution_ms,
         shapes: Enum.map(usage.shapes, &Map.take(&1, [:vcpus, :memory_gb, :executions, :execution_ms])),
         modes: usage.modes,
         series:
           usage.dates |> Enum.zip(usage.series) |> Enum.map(fn {bucket, point} -> Map.put(point, :bucket, bucket) end)
       }}
    else
      _ -> {:error, :invalid_period}
    end
  end

  def max_days, do: @max_days

  defp arg(args, key), do: Map.get(args, key) || Map.get(args, Atom.to_string(key))

  defp datetime(nil, default), do: {:ok, default}
  defp datetime(%DateTime{} = value, _default), do: {:ok, value}

  defp datetime(value, _default) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp datetime(_value, _default), do: :error

  defp iso8601(datetime), do: datetime |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
end
