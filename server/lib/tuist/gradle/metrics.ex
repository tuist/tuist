defmodule Tuist.Gradle.Metrics do
  @moduledoc "Compatibility entry point for Gradle build metrics."

  def query(project_id, opts) do
    project_id
    |> Tuist.BuildMetrics.query(Keyword.put(opts, :build_system, "gradle"))
    |> Map.new(fn
      {key, metrics} when key in [:totals, :series] ->
        {key, Map.drop(metrics, ["cache_work_avoided", "cache_work_avoided_samples"])}

      {:rows, rows} ->
        {:rows, Enum.map(rows, &Map.drop(&1, ["cache_work_avoided", "cache_work_avoided_samples"]))}

      entry ->
        entry
    end)
  end

  def dimension_values(project_id, dimension),
    do: Tuist.BuildMetrics.dimension_values(project_id, dimension, "gradle", lookback_days: nil)
end
