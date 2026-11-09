defmodule Pulse.QueryLimit do
  @moduledoc """
  Which query budget a limit failure hit, and its value.

  Storage and evaluators keep returning the bare reasons callers match on
  (`:query_scan_limit`, `:query_sample_limit`, `:query_work_limit`,
  `:query_result_limit`, `:query_intermediate_limit`, `:query_resource_limit`,
  `:query_timeout`); the detail travels beside it in the process dictionary.
  `Pulse.QueryRunner` carries it from the query worker back to the caller,
  where error rendering reads it with `take/0`.
  """

  @key {__MODULE__, :exceeded}

  @env %{
    max_scan_segments: "PULSE_QUERY_MAX_SCAN_SEGMENTS",
    max_scan_bytes: "PULSE_QUERY_MAX_SCAN_BYTES",
    max_scan_rows: "PULSE_QUERY_MAX_SCAN_ROWS",
    max_samples: "PULSE_QUERY_MAX_SAMPLES",
    max_log_samples: "PULSE_QUERY_MAX_LOG_SAMPLES",
    max_work: "PULSE_QUERY_MAX_WORK",
    max_result_points: "PULSE_QUERY_MAX_RESULT_POINTS",
    max_materialized_samples: "PULSE_QUERY_MAX_MATERIALIZED_SAMPLES",
    timeout_ms: "PULSE_QUERY_TIMEOUT_MS",
    max_heap_mb: "PULSE_QUERY_MAX_HEAP_MB"
  }

  @reasons %{
    max_scan_segments: :query_scan_limit,
    max_scan_bytes: :query_scan_limit,
    max_scan_rows: :query_scan_limit,
    metadata: :query_scan_limit,
    max_samples: :query_sample_limit,
    max_log_samples: :query_sample_limit,
    max_work: :query_work_limit,
    max_evaluation_steps: :query_work_limit,
    max_result_points: :query_result_limit,
    max_materialized_samples: :query_intermediate_limit,
    max_heap_mb: :query_resource_limit,
    timeout_ms: :query_timeout
  }

  @hint "narrow the time range or selector, or raise"

  @type detail :: %{
          optional(:metric_tiers) => %{atom() => {non_neg_integer(), non_neg_integer()}},
          limit: atom(),
          maximum: integer() | nil,
          observed: integer() | nil,
          stage: atom()
        }

  @doc """
  Record that `limit` (with configured `maximum`) was exceeded at `stage`,
  having seen at least `observed`, and return `{:error, :query_scan_limit}`.
  """
  def exceeded(limit, maximum, observed, stage) do
    Process.put(@key, %{limit: limit, maximum: maximum, observed: observed, stage: stage})
    {:error, :query_scan_limit}
  end

  @doc """
  Record any limit, for example `:max_samples` from the evaluator, without
  building an error. `stage` is `:evaluated` unless the limit is a scan budget.
  """
  def record(limit, maximum, observed, stage \\ :evaluated) do
    Process.put(@key, %{limit: limit, maximum: maximum, observed: observed, stage: stage})
    :ok
  end

  @doc "The latest recorded detail, without removing it."
  @spec peek() :: detail() | nil
  def peek, do: Process.get(@key)

  @doc """
  The detail as JSON for HTTP error bodies: `reason`, `limit`, `value`,
  `observed` and the variable (`env`) that sets it.
  """
  def to_map(nil), do: nil

  def to_map(%{limit: limit, maximum: maximum, observed: observed}) do
    %{
      "reason" => @reasons |> Map.get(limit) |> then(&(&1 && Atom.to_string(&1))),
      "limit" => Atom.to_string(limit),
      "value" => maximum,
      "observed" => if(is_integer(observed), do: observed),
      "env" => Map.get(@env, limit)
    }
  end

  @doc "The latest recorded detail, removing it."
  @spec take() :: detail() | nil
  def take, do: Process.delete(@key)

  @doc "Re-record a detail taken from another process."
  def put(nil), do: :ok
  def put(detail), do: Process.put(@key, detail) && :ok

  @doc "A one-line, human-readable description of a detail."
  @spec describe(detail() | nil) :: String.t() | nil
  def describe(nil), do: nil

  def describe(%{limit: :metadata}),
    do: "manifest pages read while planning candidate segments exceeded their metadata budget; narrow the time range"

  def describe(%{limit: :max_scan_bytes, stage: :object, maximum: remaining}),
    do: "a segment object exceeded the #{remaining} bytes left of max_scan_bytes; #{@hint} PULSE_QUERY_MAX_SCAN_BYTES"

  def describe(%{metric_tiers: tiers} = detail) do
    breakdown =
      tiers
      |> Enum.sort()
      |> Enum.map_join(", ", fn {tier, {count, bytes}} -> "#{tier}: #{count} segments / #{bytes} bytes" end)

    describe(Map.delete(detail, :metric_tiers)) <> "; candidate tiers: " <> breakdown
  end

  def describe(%{limit: limit, maximum: maximum, observed: observed, stage: stage}) do
    env = Map.get(@env, limit)

    [
      "#{limit}=#{maximum} exceeded",
      if(is_integer(observed), do: ": #{subject(stage)} at least #{observed} #{unit(limit)}", else: ""),
      if(env, do: "; #{@hint} #{env}", else: "")
    ]
    |> IO.iodata_to_binary()
  end

  defp subject(:candidates), do: "candidates in the time range total"
  defp subject(:visited), do: "the scan needed"
  defp subject(_stage), do: "the query reached"

  defp unit(:max_scan_bytes), do: "bytes"
  defp unit(:max_scan_rows), do: "rows"
  defp unit(limit) when limit in [:max_scan_segments, :metadata], do: "segments"
  defp unit(limit) when limit in [:max_samples, :max_log_samples, :max_materialized_samples], do: "samples"
  defp unit(:max_work), do: "work units"
  defp unit(:max_result_points), do: "points"
  defp unit(:max_evaluation_steps), do: "steps"
  defp unit(_limit), do: ""
end
