defmodule TuistWeb.GradleBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Gradle
  alias Tuist.Repo
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @table_page_size 25

  def mount(
        %{"gradle_build_id" => build_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    build = Gradle.get_build(build_id)

    if is_nil(build) or build.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_gradle", "Build not found.")
    end

    build = Repo.preload(build, :built_by_account)

    aggregates = Gradle.task_cache_aggregates(build_id)

    download_throughput =
      if aggregates.download_duration_ms > 0,
        do: aggregates.cache_download_bytes / (aggregates.download_duration_ms / 1000),
        else: 0

    upload_throughput =
      if aggregates.upload_duration_ms > 0,
        do: aggregates.cache_upload_bytes / (aggregates.upload_duration_ms / 1000),
        else: 0

    slug = "#{account.name}/#{project.name}"
    title = build.root_project_name || dgettext("dashboard_gradle", "Gradle Build")

    socket =
      socket
      |> assign(:build, build)
      |> assign(:cache_download_bytes, aggregates.cache_download_bytes)
      |> assign(:cache_upload_bytes, aggregates.cache_upload_bytes)
      |> assign(:download_throughput, download_throughput)
      |> assign(:upload_throughput, upload_throughput)
      |> assign(:title, title)
      |> assign(:head_title, "#{title} · #{slug} · Tuist")

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    selected_tab = params["tab"] || "overview"
    uri = URI.new!("?" <> URI.encode_query(params))

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, uri)
      |> assign_tab_data(selected_tab, params)

    {:noreply, socket}
  end

  def handle_event("search-tasks", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("tasks-filter", search)
      |> Query.put("tasks-page", "1")

    {:noreply,
     push_patch(socket,
       to:
         ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/gradle-cache/builds/#{socket.assigns.build.id}?#{query}"
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("tasks-page", "1")

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/gradle-cache/builds/#{socket.assigns.build.id}?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.put("tasks-page", "1")

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/gradle-cache/builds/#{socket.assigns.build.id}?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  defp assign_tab_data(socket, "overview", params) do
    build_id = socket.assigns.build.id

    filters = Filter.Operations.decode_filters_from_query(params, define_task_filters())
    text_filters = build_text_flop_filters(params["tasks-filter"])
    dropdown_filters = build_task_flop_filters(filters)
    sort_by = ensure_allowed_sort_by(params["tasks-sort-by"])
    sort_order = params["tasks-sort-order"] || "asc"

    flop_params = %{
      filters: text_filters ++ dropdown_filters,
      page: String.to_integer(params["tasks-page"] || "1"),
      page_size: @table_page_size,
      order_by: [sort_by],
      order_directions: [String.to_atom(sort_order)]
    }

    {tasks, meta} = Gradle.list_tasks(build_id, flop_params)

    socket
    |> assign(:tasks, tasks)
    |> assign(:tasks_page, meta.current_page)
    |> assign(:tasks_page_count, meta.total_pages)
    |> assign(:tasks_filter, params["tasks-filter"] || "")
    |> assign(:tasks_sort_by, params["tasks-sort-by"] || "started_at")
    |> assign(:tasks_sort_order, sort_order)
    |> assign(:tasks_active_filters, filters)
    |> assign(:available_filters, define_task_filters())
  end

  defp assign_tab_data(socket, "gradle-cache", params) do
    build_id = socket.assigns.build.id
    page = String.to_integer(params["cacheable-tasks-page"] || "1")

    flop_params = %{
      page: page,
      page_size: @table_page_size,
      filters: [%{field: :cacheable, op: :==, value: true}]
    }

    {cacheable_tasks, meta} = Gradle.list_tasks(build_id, flop_params)

    socket
    |> assign(:cacheable_tasks, cacheable_tasks)
    |> assign(:cacheable_tasks_page, page)
    |> assign(:cacheable_tasks_page_count, meta.total_pages)
  end

  defp assign_tab_data(socket, _tab, _params), do: socket

  defp define_task_filters do
    [
      %Filter.Filter{
        id: "outcome",
        field: :outcome,
        display_name: dgettext("dashboard_gradle", "Outcome"),
        type: :option,
        options: [:local_hit, :remote_hit, :up_to_date, :executed, :failed, :skipped, :no_source],
        options_display_names: %{
          local_hit: dgettext("dashboard_gradle", "Local hit"),
          remote_hit: dgettext("dashboard_gradle", "Remote hit"),
          up_to_date: dgettext("dashboard_gradle", "Up-to-date"),
          executed: dgettext("dashboard_gradle", "Executed"),
          failed: dgettext("dashboard_gradle", "Failed"),
          skipped: dgettext("dashboard_gradle", "Skipped"),
          no_source: dgettext("dashboard_gradle", "No source")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  defp build_text_flop_filters(nil), do: []
  defp build_text_flop_filters(""), do: []

  defp build_text_flop_filters(filter_text) do
    [%{field: :task_path, op: :=~, value: filter_text}]
  end

  defp build_task_flop_filters(filters) do
    filters
    |> Enum.map(fn filter ->
      case filter.id do
        "outcome" ->
          %{filter | value: if(filter.value, do: Atom.to_string(filter.value))}
      end
    end)
    |> Filter.Operations.convert_filters_to_flop()
  end

  defp ensure_allowed_sort_by(value) when value in ["task_path", "duration_ms", "started_at"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_sort_by(_), do: :started_at

  def sort_icon("desc"), do: "square_rounded_arrow_down"
  def sort_icon("asc"), do: "square_rounded_arrow_up"

  def sort_order_patch_value(category, current_category, current_order) do
    if category == current_category do
      if current_order == "asc", do: "desc", else: "asc"
    else
      "asc"
    end
  end

  defp cache_hit_rate(build) do
    from_cache = (build.tasks_local_hit_count || 0) + (build.tasks_remote_hit_count || 0)
    executed = build.tasks_executed_count || 0
    total = from_cache + executed

    if total == 0 do
      0.0
    else
      Float.round(from_cache / total * 100.0, 1)
    end
  end

  defp outcome_color("local_hit"), do: "success"
  defp outcome_color("remote_hit"), do: "information"
  defp outcome_color("up_to_date"), do: "information"
  defp outcome_color("executed"), do: "secondary"
  defp outcome_color("failed"), do: "destructive"
  defp outcome_color(_), do: "secondary"

  defp outcome_label("local_hit"), do: dgettext("dashboard_gradle", "Local hit")
  defp outcome_label("remote_hit"), do: dgettext("dashboard_gradle", "Remote hit")
  defp outcome_label("up_to_date"), do: dgettext("dashboard_gradle", "Up-to-date")
  defp outcome_label("executed"), do: dgettext("dashboard_gradle", "Executed")
  defp outcome_label("failed"), do: dgettext("dashboard_gradle", "Failed")
  defp outcome_label("skipped"), do: dgettext("dashboard_gradle", "Skipped")
  defp outcome_label("no_source"), do: dgettext("dashboard_gradle", "No source")
  defp outcome_label(other), do: other

  defp format_duration(duration_ms) do
    DateFormatter.format_duration_from_milliseconds(duration_ms)
  end

  defp started_after(task, build) do
    if task.started_at do
      build_started_at = NaiveDateTime.add(build.inserted_at, -build.duration_ms, :millisecond)
      diff_ms = NaiveDateTime.diff(task.started_at, build_started_at, :millisecond)
      format_started_after_ms(max(diff_ms, 0))
    else
      dgettext("dashboard_gradle", "—")
    end
  end

  defp format_started_after_ms(0), do: "0.00s"
  defp format_started_after_ms(ms) when ms < 1000, do: "#{ms}ms"

  defp format_started_after_ms(ms) do
    hours = div(ms, 3_600_000)
    remainder = rem(ms, 3_600_000)
    minutes = div(remainder, 60_000)
    remainder = rem(remainder, 60_000)
    seconds = div(remainder, 1_000)
    millis = rem(remainder, 1_000)

    parts = []
    parts = if hours > 0, do: parts ++ ["#{hours}h"], else: parts
    parts = if minutes > 0, do: parts ++ ["#{minutes}m"], else: parts

    parts =
      if ms > 60_000 and seconds > 0 do
        parts ++ ["#{seconds}s"]
      else
        seconds_with_ms = seconds + millis / 1000
        parts ++ [:erlang.float_to_binary(Float.round(seconds_with_ms, 2), decimals: 2) <> "s"]
      end

    Enum.join(parts, " ")
  end
end
