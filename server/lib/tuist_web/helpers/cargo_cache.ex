defmodule TuistWeb.Helpers.CargoCache do
  @moduledoc false
  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Cargo.CacheMetrics
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Utilities.Query

  def prefix("cas-outputs"), do: "cache-cas"
  def prefix(_), do: "cache-tasks"

  def rows(metrics, section) do
    key = if section == "cas-outputs", do: :cas_outputs, else: :tasks

    metrics
    |> Map.get(:details, %{})
    |> Map.get(key, [])
    |> Enum.with_index()
    |> Enum.map(fn {row, index} -> Map.put(row, :id, "cargo-#{key}-#{index}") end)
  end

  def page(rows, search, sort, status, page) do
    search = String.downcase(search)

    rows =
      Enum.filter(
        rows,
        &(String.contains?(String.downcase("#{Map.get(&1, :name, "")} #{&1.key}"), search) and
            (status == "all" or result(&1.status) == status))
      )

    rows =
      Enum.sort_by(rows, fn row ->
        case sort do
          "size" -> {-Map.get(row, :size_bytes, 0), row.id}
          "duration" -> {-Map.get(row, :duration_ns, Map.get(row, :read_duration_ns, 0)), row.id}
          "key" -> {row.key, row.id}
          _ -> {Map.get(row, :name, row.key), row.id}
        end
      end)

    pages = max(ceil(length(rows) / 20), 1)
    page = min(page, pages)
    %{rows: Enum.slice(rows, (page - 1) * 20, 20), pages: pages, page: page}
  end

  def patch(uri, section, key, value),
    do: "?#{uri.query |> Query.put("#{prefix(section)}-#{key}", value) |> Query.put("#{prefix(section)}-page", "1")}"

  def statuses("cas-outputs"), do: ~w(downloaded uploaded present failed)
  def statuses(_), do: ~w(hit miss)
  def result(status) when status in ["unconsulted", "verification"], do: "miss"
  def result(status), do: status
  def sorts("cas-outputs"), do: ~w(key size duration)
  def sorts(_), do: ~w(name key duration)

  def status_label("hit"), do: dgettext("dashboard_builds", "Hit")

  def status_label(status) when status in ["miss", "unconsulted", "verification"],
    do: dgettext("dashboard_builds", "Missed")

  def status_label("downloaded"), do: dgettext("dashboard_builds", "Download")
  def status_label("uploaded"), do: dgettext("dashboard_builds", "Upload")
  def status_label("present"), do: dgettext("dashboard_builds", "Already present")
  def status_label("failed"), do: dgettext("dashboard_builds", "Failed")
  def status_label(_), do: dgettext("dashboard_builds", "All statuses")

  def status_description("hit"), do: dgettext("dashboard_builds", "Reused cached outputs instead of compiling.")

  def status_description("miss"),
    do: dgettext("dashboard_builds", "Checked the cache but could not reuse cached outputs.")

  def status_description("unconsulted"),
    do: dgettext("dashboard_builds", "Compiled to learn the task inputs for future cache reuse.")

  def status_description("verification"),
    do: dgettext("dashboard_builds", "Rebuilt to compare fresh outputs with cached outputs and verify cache correctness.")

  def color(status) when status in ["hit", "downloaded"], do: "focus"
  def color("uploaded"), do: "secondary"
  def color(status) when status in ["miss", "unconsulted", "verification"], do: "warning"
  def color("failed"), do: "destructive"
  def color(_), do: "neutral"

  def sort_label("name"), do: dgettext("dashboard_builds", "Name")
  def sort_label("size"), do: dgettext("dashboard_builds", "Size")
  def sort_label("duration"), do: dgettext("dashboard_builds", "Duration")
  def sort_label(_), do: dgettext("dashboard_builds", "Key")

  def segments(metrics, "cacheable-tasks") do
    case Map.get(metrics, :details) do
      nil ->
        [
          %{name: status_label("hit"), count: metrics.hits, color: "var:hits-chart-legend-remote"},
          %{name: status_label("miss"), count: CacheMetrics.task_misses(metrics), color: "var:hits-chart-legend-missed"}
        ]

      _ ->
        segments_for(rows(metrics, "cacheable-tasks"), statuses("cacheable-tasks"))
    end
  end

  def segments(metrics, "cas-outputs"), do: segments_for(rows(metrics, "cas-outputs"), ~w(downloaded uploaded))

  defp segments_for(rows, statuses) do
    Enum.map(statuses, fn status ->
      %{name: status_label(status), count: Enum.count(rows, &(result(&1.status) == status)), color: chart_color(status)}
    end)
  end

  defp chart_color(status) when status in ["hit", "downloaded"], do: "var:hits-chart-legend-remote"
  defp chart_color("miss"), do: "var:hits-chart-legend-missed"
  defp chart_color("uploaded"), do: "var:hits-chart-legend-local"

  def latency(rows, operation, type) do
    key = if operation == "read", do: :read_duration_ns, else: :write_duration_ns
    values = rows |> Enum.flat_map(fn row -> if Map.has_key?(row, key), do: [row[key]], else: [] end) |> Enum.sort()
    metrics = Map.new(~w(avg p99 p90 p50)a, fn metric -> {metric, duration(statistic(values, metric))} end)
    %{empty: values == [], metrics: metrics, value: metrics[String.to_existing_atom(type)]}
  end

  defp statistic([], _), do: nil
  defp statistic(values, :avg), do: Enum.sum(values) / length(values)

  defp statistic(values, percentile) do
    fraction = %{p99: 0.99, p90: 0.9, p50: 0.5}[percentile]
    Enum.at(values, max(ceil(length(values) * fraction) - 1, 0))
  end

  def duration(nil), do: dgettext("dashboard_builds", "No data")
  def duration(ns), do: DateFormatter.format_duration_from_milliseconds(ns / 1_000_000)

  def throughput(rows, operation) do
    status = if operation == "download", do: "downloaded", else: "uploaded"
    rows = Enum.filter(rows, &(&1.status == status and &1.operation == operation and &1.duration_ns > 0))
    duration = Enum.sum(Enum.map(rows, & &1.duration_ns))
    bytes = Enum.sum(Enum.map(rows, & &1.size_bytes))

    %{
      empty: rows == [],
      value: ThroughputFormatter.format_throughput(if(duration > 0, do: bytes * 1_000_000_000 / duration, else: 0))
    }
  end

  def references(task) do
    task
    |> Map.get(:cas_keys, [])
    |> Enum.uniq()
    |> Enum.map(&%{key: &1, label: dgettext("dashboard_builds", "CAS object:")})
  end
end
