defmodule TuistWeb.ModulesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ModuleInvalidationsTable
  import TuistWeb.Components.Skeleton

  alias Tuist.Builds.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @sort_options ~w(invalidations hit_rate blast_radius)
  @per_page 25
  # The query returns one row per module, so this bounds the project's module
  # count rather than a growing event stream.
  @max_modules 5_000

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_cache", "Modules")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("module-cache"))

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "analytics-environment",
              "analytics-date-range",
              "analytics-start-date",
              "analytics-end-date",
              "sort-by",
              "sort-order",
              "analytics-selected-widget",
              "miss-reason",
              "q",
              "after",
              "before"
            ])
          )
      )

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign_modules(params)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: account, selected_project: project}} = socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{account.name}/#{project.name}/module-cache/modules?#{query_params}")}
  end

  def handle_event("select_miss_reason", %{"type" => type}, %{assigns: assigns} = socket)
      when type in ~w(all changed upstream cold) do
    query_params = Query.put(assigns.uri.query, "miss-reason", type)
    path = "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/module-cache/modules"

    {:noreply, push_patch(socket, to: "#{path}?#{query_params}")}
  end

  def handle_event(
        "select_widget",
        %{"widget" => widget},
        %{assigns: %{selected_account: account, selected_project: project}} = socket
      ) do
    query_params = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)

    {:noreply, push_patch(socket, to: "/#{account.name}/#{project.name}/module-cache/modules?#{query_params}")}
  end

  def handle_event(
        "search",
        %{"q" => query},
        %{assigns: %{selected_account: account, selected_project: project}} = socket
      ) do
    query_params =
      socket.assigns.uri.query
      |> Query.put("q", query)
      |> Query.drop("after")
      |> Query.drop("before")

    {:noreply, push_patch(socket, to: "/#{account.name}/#{project.name}/module-cache/modules?#{query_params}")}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  def filter_modules(modules, search) when search in [nil, ""], do: modules

  def filter_modules(modules, search) do
    query = String.downcase(search)
    Enum.filter(modules, &String.contains?(String.downcase(&1.name), query))
  end

  defp assign_modules(socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    sort_by = if params["sort-by"] in @sort_options, do: params["sort-by"], else: "invalidations"
    sort_order = if params["sort-order"] in ~w(asc desc), do: params["sort-order"], else: default_sort_order(sort_by)
    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    socket =
      socket
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign(:search, params["q"] || "")
      |> assign(:after_cursor, params["after"])
      |> assign(:before_cursor, params["before"])
      |> assign(:analytics_selected_widget, params["analytics-selected-widget"] || "misses")
      |> assign(:selected_miss_reason, params["miss-reason"] || "all")

    opts = analytics_opts(socket.assigns)
    default_branch = socket.assigns.selected_project.default_branch || "main"

    # Sorting, searching and paging all run over the loaded list, so only a
    # change to what the query itself selects has to go back to ClickHouse.
    if opts == socket.assigns[:modules_opts] do
      socket
    else
      socket
      |> assign(:modules_opts, opts)
      |> assign_async([:modules], fn ->
        {:ok, %{modules: opts |> Keyword.put(:limit, @max_modules) |> Analytics.module_invalidations()}}
      end)
      |> assign_async([:timeseries, :miss_reasons_series, :modules_series, :module_count], fn ->
        {:ok,
         %{
           timeseries: opts |> Analytics.module_invalidation_timeseries() |> with_hit_rates(),
           miss_reasons_series: Analytics.module_miss_reasons_timeseries(opts),
           modules_series: Analytics.modules_timeseries(opts),
           module_count: Analytics.module_count(Keyword.put(opts, :git_branch, default_branch))
         }}
      end)
    end
  end

  defp with_hit_rates(timeseries) do
    hit_rates =
      timeseries.invalidations
      |> Enum.zip(timeseries.reuses)
      |> Enum.map(fn {misses, hits} ->
        case misses + hits do
          0 -> 0.0
          total -> Float.round(hits / total * 100, 1)
        end
      end)

    Map.put(timeseries, :hit_rates, hit_rates)
  end

  @doc """
  Totals for the analytics widgets.

  None of it comes from the table, which lists only the modules that missed at
  least once. The module count is the project's latest commit on its default
  branch, and the rest come from the series, which cover every module.
  """
  def analytics_totals(module_count, timeseries, miss_reasons) do
    %{
      modules: module_count,
      hits: Enum.sum(timeseries.reuses),
      misses: Enum.sum(timeseries.invalidations),
      changed: Enum.sum(miss_reasons.changed),
      upstream: Enum.sum(miss_reasons.upstream),
      cold: Enum.sum(miss_reasons.cold)
    }
  end

  def miss_reason_value(totals, "changed"), do: totals.changed
  def miss_reason_value(totals, "upstream"), do: totals.upstream
  def miss_reason_value(totals, "cold"), do: totals.cold
  def miss_reason_value(totals, _all), do: totals.misses

  def miss_reason_title("changed"), do: dgettext("dashboard_cache", "Changed misses")
  def miss_reason_title("upstream"), do: dgettext("dashboard_cache", "Upstream misses")
  def miss_reason_title("cold"), do: dgettext("dashboard_cache", "Cold misses")
  def miss_reason_title(_all), do: dgettext("dashboard_cache", "Misses")

  def miss_reason_color("changed"), do: "primary"
  def miss_reason_color("upstream"), do: "secondary"
  def miss_reason_color("cold"), do: "tertiary"
  def miss_reason_color(_all), do: "destructive"

  defp analytics_opts(%{
         selected_project: project,
         analytics_period: {start_datetime, end_datetime},
         analytics_environment: env
       }) do
    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    case env do
      "ci" -> Keyword.put(opts, :is_ci, true)
      "local" -> Keyword.put(opts, :is_ci, false)
      _ -> opts
    end
  end

  defp sort_modules(modules, "blast_radius", order), do: sort_by_value(modules, &(&1.blast_radius || -1), order)
  defp sort_modules(modules, "hit_rate", order), do: sort_by_value(modules, & &1.hit_rate, order)

  defp sort_modules(modules, field, order),
    do: sort_by_value(modules, &Map.fetch!(&1, String.to_existing_atom(field)), order)

  # Cursors address rows by position, so ties have to break the same way on
  # every render. The name is the tiebreaker because it is what the cursor
  # itself carries.
  defp sort_by_value(modules, key_fun, "asc"), do: Enum.sort_by(modules, &{key_fun.(&1), &1.name})
  defp sort_by_value(modules, key_fun, _desc), do: Enum.sort_by(modules, &{-key_fun.(&1), &1.name})

  # Each column opens on its worst-first direction: most misses, fewest hits,
  # most dependents.
  defp default_sort_order("hit_rate"), do: "asc"
  defp default_sort_order(_field), do: "desc"

  @doc """
  Patch for clicking a sortable column header, which flips its direction.
  """
  def column_patch_sort(%{uri: uri, sort_by: sort_by, sort_order: sort_order}, column) do
    order =
      case {sort_by == column, sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> default_sort_order(column)
      end

    sort_query(uri, column, order)
  end

  @doc """
  Patch for picking a column from the sort dropdown, which opens it on its own
  default direction.
  """
  def sort_dropdown_patch(uri, column), do: sort_query(uri, column, default_sort_order(column))

  # A cursor addresses a row by position, so it means nothing once the order
  # changes.
  defp sort_query(uri, column, order) do
    query =
      uri.query
      |> Query.put("sort-by", column)
      |> Query.put("sort-order", order)
      |> Query.drop("after")
      |> Query.drop("before")

    "?#{query}"
  end

  @doc """
  Slices an already sorted and filtered list into the page addressed by the
  `after`/`before` cursors, which are module names. A cursor that is no longer
  in the list (the search or sort changed under it) falls back to the first
  page.
  """
  def page_of(modules, after_cursor, before_cursor) do
    offset =
      case {cursor_index(modules, after_cursor), cursor_index(modules, before_cursor)} do
        {nil, nil} -> 0
        {nil, before_index} -> max(before_index - @per_page, 0)
        {after_index, _} -> after_index + 1
      end

    rows = Enum.slice(modules, offset, @per_page)

    %{
      rows: rows,
      has_previous_page: offset > 0,
      has_next_page: offset + length(rows) < length(modules),
      start_cursor: rows |> List.first() |> cursor(),
      end_cursor: rows |> List.last() |> cursor()
    }
  end

  defp cursor_index(_modules, cursor) when cursor in [nil, ""], do: nil
  defp cursor_index(modules, cursor), do: Enum.find_index(modules, &(&1.name == cursor))

  defp cursor(nil), do: nil
  defp cursor(module), do: module.name

  def sort_label("hit_rate"), do: dgettext("dashboard_cache", "Cache hit rate")
  def sort_label("blast_radius"), do: dgettext("dashboard_cache", "Dependents")
  def sort_label(_), do: dgettext("dashboard_cache", "Misses")

  defp environment_label("local"), do: dgettext("dashboard_cache", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_cache", "CI")
  defp environment_label(_), do: dgettext("dashboard_cache", "Any")
end
