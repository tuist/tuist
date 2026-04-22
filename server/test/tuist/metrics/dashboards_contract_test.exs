defmodule Tuist.Metrics.DashboardsContractTest do
  @moduledoc """
  Contract test between the bundled Grafana dashboards and the server's
  metric schema. Every `tuist_*` metric referenced by a panel query must
  correspond to a metric declared in `Tuist.Metrics.Schema`.

  Catches the drift that's easy to miss during refactors:

    * a metric gets renamed on the server but the dashboard still queries
      the old name (scrape works, panels silently show "No data");
    * a new dashboard is added referencing a metric that was never
      declared in the schema (same failure mode).

  Histogram references (`_bucket`, `_sum`, `_count`) are matched against
  the base histogram name.
  """
  use ExUnit.Case, async: true

  alias Tuist.Metrics.Schema

  @dashboards_dir Path.expand("../../../../grafana/src/dashboards", __DIR__)
  @histogram_suffixes ["_bucket", "_sum", "_count"]

  setup_all do
    schema_names = MapSet.new(Schema.definitions(), & &1.name)
    histogram_base_names = for %{type: :histogram, name: n} <- Schema.definitions(), into: MapSet.new(), do: n

    %{schema_names: schema_names, histogram_base_names: histogram_base_names}
  end

  test "every tuist_* metric referenced by a dashboard exists in the schema", ctx do
    dashboards = Path.wildcard(Path.join(@dashboards_dir, "*.json"))
    assert dashboards != [], "No dashboards found under #{@dashboards_dir}"

    referenced =
      dashboards
      |> Enum.flat_map(&extract_metric_names_from_file/1)
      |> MapSet.new()

    # Every reference should resolve to either a literal schema metric or a
    # histogram base name (after stripping _bucket/_sum/_count).
    unresolved =
      Enum.reject(referenced, fn name ->
        MapSet.member?(ctx.schema_names, name) or
          MapSet.member?(ctx.histogram_base_names, strip_histogram_suffix(name))
      end)

    assert unresolved == [],
           """
           Dashboards reference metrics that are not declared in Tuist.Metrics.Schema:

               #{Enum.join(unresolved, "\n    ")}

           Either add the metric to the schema or fix the dashboard query.
           """
  end

  defp extract_metric_names_from_file(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("panels", [])
    |> Enum.flat_map(&extract_from_panel/1)
  end

  defp extract_from_panel(%{"targets" => targets}) when is_list(targets) do
    Enum.flat_map(targets, fn target ->
      case Map.get(target, "expr", "") do
        expr when is_binary(expr) ->
          ~r/\btuist_[a-z0-9_]+/
          |> Regex.scan(expr)
          |> List.flatten()

        _ ->
          []
      end
    end)
  end

  defp extract_from_panel(_), do: []

  defp strip_histogram_suffix(name) do
    Enum.reduce_while(@histogram_suffixes, name, fn suffix, acc ->
      if String.ends_with?(acc, suffix) do
        {:halt, String.slice(acc, 0, byte_size(acc) - byte_size(suffix))}
      else
        {:cont, acc}
      end
    end)
  end
end
