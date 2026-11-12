defmodule Pulse.OTLP.Rejections do
  @moduledoc """
  Diagnostics for records an OTLP receiver drops from an otherwise accepted
  export: a counter per signal and fixed reason, a rate-limited warning naming
  the reason and service, and a partial-success message listing reasons.

  Rejections are `%{{reason, service} => count}`. Reasons come from a fixed
  vocabulary; services are only logged (bounded and sanitized), never used as
  metric labels. Payload contents and credentials are never logged.
  """

  alias Pulse.OTLP.Traces

  require Logger

  @generic "invalid records rejected"
  @log_interval_ms 60_000

  @doc "Fixed rejection reasons for `signal`."
  def reasons(:traces), do: Traces.rejection_reasons() ++ [:retention_expired]
  def reasons(_signal), do: []

  @spec record(atom(), String.t(), map()) :: :ok
  def record(_signal, _tenant, rejections) when map_size(rejections) == 0, do: :ok

  def record(signal, tenant, rejections) do
    known = reasons(signal)

    rejections
    |> Enum.group_by(fn {{reason, _service}, _} -> if reason in known, do: reason, else: :other end)
    |> Enum.each(fn {reason, entries} ->
      count = entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      Pulse.SelfMetrics.rejected_records(signal, reason, count)

      if Pulse.SelfMetrics.due?({:rejection_log, signal, reason}, @log_interval_ms),
        do: log(signal, tenant, reason, count, entries)
    end)
  end

  defp log(signal, tenant, reason, count, entries) do
    services = entries |> Enum.map(fn {{_, service}, _} -> service(service) end) |> Enum.uniq() |> Enum.take(5)

    Logger.warning(
      "OTLP #{signal} records rejected: reason=#{reason} count=#{count} tenant=#{service(tenant)} " <>
        "services=#{Enum.join(services, ",")} (logged at most once per minute per reason)"
    )
  end

  @doc "Partial-success `errorMessage`: rejected counts by reason, or the generic text."
  @spec message(map()) :: String.t()
  def message(rejections) when map_size(rejections) == 0, do: @generic

  def message(rejections) do
    rejections
    |> Enum.reduce(%{}, fn {{reason, _service}, count}, acc -> Map.update(acc, reason, count, &(&1 + count)) end)
    |> Enum.sort_by(fn {reason, count} -> {-count, reason} end)
    |> Enum.take(8)
    |> Enum.map_join(", ", fn {reason, count} -> "#{reason}=#{count}" end)
    |> then(&"#{@generic}: #{&1}")
  end

  # Service names come from incoming telemetry: bound length and drop controls.
  defp service(nil), do: "unknown"

  defp service(value) when is_binary(value) do
    value
    |> String.slice(0, 64)
    |> String.replace(~r/[^\x21-\x7e]/u, "_")
  end

  defp service(_), do: "unknown"
end
