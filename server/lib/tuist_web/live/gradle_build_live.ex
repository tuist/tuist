defmodule TuistWeb.GradleBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.MachineMetricsCharts
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @table_page_size 25

  @doc """
  Assigns gradle build data to the socket during mount.
  Called from BuildRunLive when the project is a gradle project.
  """
  def assign_mount(socket, build_id) do
    %{selected_project: project, selected_account: account} = socket.assigns

    case Gradle.get_build(build_id) do
      {:error, :not_found} ->
        raise NotFoundError, dgettext("dashboard_gradle", "Build not found.")

      {:ok, build} ->
        if build.project_id != project.id do
          raise NotFoundError, dgettext("dashboard_gradle", "Build not found.")
        end

        assign_build(socket, build, account)
    end
  end

  defp assign_build(socket, build, account) do
    build = Repo.preload(build, :built_by_account)

    test_run =
      case Tests.get_latest_test_by_gradle_build_id(build.id) do
        {:ok, test} -> test
        {:error, :not_found} -> nil
      end

    build = ClickHouseRepo.preload(build, [:machine_metrics])

    build_started_at = Gradle.build_started_at(build.id)
    aggregates = Gradle.task_cache_aggregates(build.id)
    configuration_operations = Gradle.list_configuration_operations(build.id)
    artifact_transforms = Gradle.list_artifact_transforms(build.id)
    machine_metrics = build.machine_metrics

    download_throughput =
      if aggregates.download_duration_ms > 0,
        do: aggregates.cache_download_bytes / (aggregates.download_duration_ms / 1000),
        else: 0

    upload_throughput =
      if aggregates.upload_duration_ms > 0,
        do: aggregates.cache_upload_bytes / (aggregates.upload_duration_ms / 1000),
        else: 0

    slug = "#{account.name}/#{socket.assigns.selected_project.name}"
    title = build.root_project_name || dgettext("dashboard_gradle", "Gradle Build")

    local_hits = build.tasks_local_hit_count || 0
    remote_hits = build.tasks_remote_hit_count || 0
    from_cache = local_hits + remote_hits
    cacheable = build.cacheable_tasks_count || 0

    configuration_duration_ms =
      configuration_operations
      |> Enum.filter(&(&1.phase == "build"))
      |> Enum.map(& &1.duration_ms)
      |> Enum.sum()

    configuration_timeline_range = configuration_timeline_range(configuration_operations)

    socket
    |> assign(:build, build)
    |> assign(:test_run, test_run)
    |> assign(:build_started_at, build_started_at)
    |> assign(:from_cache, from_cache)
    |> assign(:cache_misses, cacheable - from_cache)
    |> assign(:cacheable_count, cacheable)
    |> assign(:cache_hit_rate, Gradle.cache_hit_rate(build))
    |> assign(:cache_download_bytes, aggregates.cache_download_bytes)
    |> assign(:cache_upload_bytes, aggregates.cache_upload_bytes)
    |> assign(:download_throughput, download_throughput)
    |> assign(:upload_throughput, upload_throughput)
    |> assign(:confirmed_remote_cache_miss_count, aggregates.confirmed_remote_cache_miss_count)
    |> assign(:confirmed_remote_cache_miss_duration_ms, aggregates.confirmed_remote_cache_miss_duration_ms)
    |> assign(:remote_cache_entries_stored_count, aggregates.remote_cache_entries_stored_count)
    |> assign(:configuration_operations, configuration_operations)
    |> assign(:configuration_timeline_range, configuration_timeline_range)
    |> assign(:configuration_duration_ms, configuration_duration_ms)
    |> assign(:artifact_transforms, artifact_transforms)
    |> assign(:artifact_transform_duration_ms, Enum.sum_by(artifact_transforms, & &1.duration_ms))
    |> assign(:title, title)
    |> assign(:head_title, "#{title} · #{slug} · Tuist")
    |> assign(:machine_metrics, machine_metrics)
  end

  @doc """
  Assigns gradle build tab data to the socket during handle_params.
  Called from BuildRunLive when the project is a gradle project.
  """
  def assign_handle_params(socket, params) do
    selected_tab = params["tab"] || "overview"
    uri = URI.new!("?" <> URI.encode_query(params))

    socket
    |> assign(:selected_tab, selected_tab)
    |> assign(:uri, uri)
    |> assign_tab_data(selected_tab, params)
  end

  defp build_run_path(socket) do
    %{selected_account: account, selected_project: project, build: build} = socket.assigns
    "/#{account.name}/#{project.name}/builds/build-runs/#{build.id}"
  end

  def handle_event("search-tasks", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("tasks-filter", search)
      |> Query.put("tasks-page", "1")

    {:noreply, push_patch(socket, to: "#{build_run_path(socket)}?#{query}")}
  end

  def handle_event("search-cacheable-tasks", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("cacheable-tasks-filter", search)
      |> Query.put("cacheable-tasks-page", "1")

    {:noreply, push_patch(socket, to: "#{build_run_path(socket)}?#{query}")}
  end

  def handle_event("search-configuration-operations", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("configuration-operations-filter", search)
      |> Query.put("configuration-operations-page", "1")

    {:noreply, push_patch(socket, to: "#{build_run_path(socket)}?#{query}")}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    page_param =
      if socket.assigns.selected_tab == "gradle-cache",
        do: "cacheable-tasks-page",
        else: "tasks-page"

    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put(page_param, "1")

    {:noreply,
     socket
     |> push_patch(to: "#{build_run_path(socket)}?#{URI.encode_query(updated_params)}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    page_param =
      if socket.assigns.selected_tab == "gradle-cache",
        do: "cacheable-tasks-page",
        else: "tasks-page"

    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.put(page_param, "1")

    {:noreply,
     socket
     |> push_patch(to: "#{build_run_path(socket)}?#{URI.encode_query(updated_query_params)}")
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

    filters =
      Filter.Operations.decode_filters_from_query(params, define_cacheable_task_filters())

    text_filters = build_text_flop_filters(params["cacheable-tasks-filter"])
    dropdown_filters = build_cacheable_task_flop_filters(filters)
    sort_by = ensure_allowed_cacheable_sort_by(params["cacheable-tasks-sort-by"])
    sort_order = params["cacheable-tasks-sort-order"] || "desc"

    flop_params = %{
      filters:
        [
          %{field: :cacheable, op: :==, value: true},
          %{field: :outcome, op: :!=, value: "up_to_date"}
        ] ++ text_filters ++ dropdown_filters,
      page: String.to_integer(params["cacheable-tasks-page"] || "1"),
      page_size: @table_page_size,
      order_by: [sort_by],
      order_directions: [String.to_atom(sort_order)]
    }

    {cacheable_tasks, meta} = Gradle.list_tasks(build_id, flop_params)

    socket
    |> assign(:cacheable_tasks, cacheable_tasks)
    |> assign(:cacheable_tasks_page, meta.current_page)
    |> assign(:cacheable_tasks_page_count, meta.total_pages)
    |> assign(:cacheable_tasks_filter, params["cacheable-tasks-filter"] || "")
    |> assign(:cacheable_tasks_sort_by, params["cacheable-tasks-sort-by"] || "duration_ms")
    |> assign(:cacheable_tasks_sort_order, sort_order)
    |> assign(:cacheable_tasks_active_filters, filters)
    |> assign(:available_filters, define_cacheable_task_filters())
  end

  defp assign_tab_data(socket, "build-setup", params) do
    filter_text = params["configuration-operations-filter"] || ""
    phase = configuration_phase_filter(params["configuration-operations-phase"])
    sort_by = configuration_operations_sort_by(params["configuration-operations-sort-by"])
    sort_order = configuration_operations_sort_order(params["configuration-operations-sort-order"])

    filtered_operations = filter_configuration_operations(socket.assigns.configuration_operations, filter_text, phase)

    sorted_operations = sort_configuration_operations(filtered_operations, sort_by, sort_order)

    {configuration_operations, page, page_count} =
      paginate_configuration_operations(
        sorted_operations,
        params["configuration-operations-page"]
      )

    socket
    |> assign(
      :configuration_timeline_operations,
      configuration_timeline_operations(filtered_operations, socket.assigns.configuration_timeline_range)
    )
    |> assign(:configuration_operations_table, configuration_operations)
    |> assign(:configuration_operations_filter, filter_text)
    |> assign(:configuration_operations_phase, phase)
    |> assign(:configuration_operations_sort_by, sort_by)
    |> assign(:configuration_operations_sort_order, sort_order)
    |> assign(:configuration_operations_page, page)
    |> assign(:configuration_operations_page_count, page_count)
  end

  defp assign_tab_data(socket, _tab, _params), do: socket

  defp filter_configuration_operations(operations, filter_text, phase) do
    search = String.downcase(filter_text)

    Enum.filter(operations, fn operation ->
      phase_matches? = is_nil(phase) or operation.phase == phase

      search_matches? =
        search == "" or
          String.contains?(String.downcase(configuration_operation_searchable_text(operation)), search)

      phase_matches? and search_matches?
    end)
  end

  defp sort_configuration_operations(operations, "started_at", sort_order) do
    Enum.sort(operations, fn first, second ->
      case NaiveDateTime.compare(first.started_at, second.started_at) do
        :lt -> sort_order == "asc"
        :gt -> sort_order == "desc"
        :eq -> first.phase <= second.phase
      end
    end)
  end

  defp sort_configuration_operations(operations, sort_by, sort_order) do
    direction = if sort_order == "desc", do: :desc, else: :asc

    Enum.sort_by(operations, &configuration_operation_sort_value(&1, sort_by), direction)
  end

  defp configuration_operation_sort_value(operation, "duration_ms"), do: operation.duration_ms
  defp configuration_operation_sort_value(operation, "scope"), do: configuration_operation_scope(operation)
  defp configuration_operation_sort_value(operation, "phase"), do: operation.phase
  defp configuration_operation_sort_value(operation, _started_at), do: operation.started_at

  defp paginate_configuration_operations(operations, page_param) do
    page_count = max(div(length(operations) + @table_page_size - 1, @table_page_size), 1)
    page = page_param |> parse_configuration_operations_page() |> min(page_count)
    offset = (page - 1) * @table_page_size

    {Enum.slice(operations, offset, @table_page_size), page, page_count}
  end

  defp parse_configuration_operations_page(nil), do: 1

  defp parse_configuration_operations_page(page) do
    case Integer.parse(page) do
      {value, ""} when value > 0 -> value
      _ -> 1
    end
  end

  defp configuration_timeline_range(operations) do
    operations = Enum.filter(operations, & &1.started_at)

    case operations do
      [] ->
        %{start_at: nil, duration_ms: 0}

      [first | rest] ->
        start_at = Enum.reduce(rest, first.started_at, &min_configuration_started_at/2)

        end_at =
          Enum.reduce(rest, configuration_operation_end_at(first), fn operation, latest_end_at ->
            max_configuration_ended_at(configuration_operation_end_at(operation), latest_end_at)
          end)

        %{
          start_at: start_at,
          duration_ms: max(NaiveDateTime.diff(end_at, start_at, :millisecond), 1)
        }
    end
  end

  defp min_configuration_started_at(operation, started_at) do
    case NaiveDateTime.compare(operation.started_at, started_at) do
      :lt -> operation.started_at
      _ -> started_at
    end
  end

  defp max_configuration_ended_at(operation_end_at, latest_end_at) do
    case NaiveDateTime.compare(operation_end_at, latest_end_at) do
      :gt -> operation_end_at
      _ -> latest_end_at
    end
  end

  defp configuration_operation_end_at(operation) do
    NaiveDateTime.add(operation.started_at, operation.duration_ms, :millisecond)
  end

  defp configuration_timeline_operations(_operations, %{start_at: nil}), do: []

  defp configuration_timeline_operations(operations, %{start_at: start_at, duration_ms: duration_ms}) do
    operations
    |> sort_configuration_operations("started_at", "asc")
    |> Enum.map(fn operation ->
      %{
        operation: operation,
        start_percentage: NaiveDateTime.diff(operation.started_at, start_at, :millisecond) / duration_ms * 100,
        duration_percentage: operation.duration_ms / duration_ms * 100
      }
    end)
  end

  defp configuration_timeline_bar_style(timeline_operation) do
    "--configuration-operation-start: #{timeline_operation.start_percentage}%; " <>
      "--configuration-operation-duration: #{timeline_operation.duration_percentage}%;"
  end

  defp configuration_operation_searchable_text(operation) do
    Enum.join(
      [operation.phase, configuration_operation_scope(operation), operation.build_path, operation.project_path],
      " "
    )
  end

  defp configuration_operation_scope(%{project_path: project_path}) when project_path != "", do: project_path

  defp configuration_operation_scope(%{build_path: ":"}), do: dgettext("dashboard_gradle", "Root build")
  defp configuration_operation_scope(%{build_path: build_path}), do: build_path

  defp root_build_configuration_operation?(operation) do
    operation.project_path == "" and operation.build_path == ":"
  end

  defp configuration_phase_filter(phase) when phase in ["build", "settings", "project"], do: phase
  defp configuration_phase_filter(_), do: nil

  defp configuration_operations_sort_by(value) when value in ["started_at", "duration_ms", "phase", "scope"], do: value

  defp configuration_operations_sort_by(_), do: "started_at"

  defp configuration_operations_sort_order(value) when value in ["asc", "desc"], do: value
  defp configuration_operations_sort_order(_), do: "asc"

  defp configuration_operations_sort_label("duration_ms"), do: dgettext("dashboard_gradle", "Duration")
  defp configuration_operations_sort_label("phase"), do: dgettext("dashboard_gradle", "Phase")
  defp configuration_operations_sort_label("scope"), do: dgettext("dashboard_gradle", "Configured unit")
  defp configuration_operations_sort_label(_), do: dgettext("dashboard_gradle", "Started after")

  defp configuration_operations_phase_label(nil), do: dgettext("dashboard_gradle", "All phases")
  defp configuration_operations_phase_label(phase), do: configuration_phase_label(phase)

  defp configuration_operations_phase_patch(uri_query, phase) do
    query =
      if is_nil(phase) do
        Query.drop(uri_query, "configuration-operations-phase")
      else
        Query.put(uri_query, "configuration-operations-phase", phase)
      end

    "?#{Query.put(query, "configuration-operations-page", "1")}"
  end

  defp configuration_operations_sort_patch(uri_query, sort_by, sort_order) do
    "?#{uri_query |> Query.put("configuration-operations-sort-by", sort_by) |> Query.put("configuration-operations-sort-order", sort_order) |> Query.drop("configuration-operations-page")}"
  end

  defp configuration_operations_column_sort_patch(uri_query, sort_by, current_sort_by, current_sort_order) do
    sort_order =
      if sort_by == current_sort_by,
        do: if(current_sort_order == "asc", do: "desc", else: "asc"),
        else: "asc"

    configuration_operations_sort_patch(uri_query, sort_by, sort_order)
  end

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
    [%{field: :task_path, op: :like, value: filter_text}]
  end

  defp build_task_flop_filters(filters) do
    filters
    |> Enum.map(fn filter ->
      "outcome" = filter.id
      %{filter | value: if(filter.value, do: Atom.to_string(filter.value))}
    end)
    |> Filter.Operations.convert_filters_to_flop()
  end

  defp ensure_allowed_sort_by(value) when value in ["task_path", "duration_ms", "started_at"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_sort_by(_), do: :started_at

  defp define_cacheable_task_filters do
    [
      %Filter.Filter{
        id: "outcome",
        field: :outcome,
        display_name: dgettext("dashboard_gradle", "Status"),
        type: :option,
        options: [:local_hit, :remote_hit, :executed],
        options_display_names: %{
          local_hit: dgettext("dashboard_gradle", "Local"),
          remote_hit: dgettext("dashboard_gradle", "Remote"),
          executed: dgettext("dashboard_gradle", "Missed")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  defp build_cacheable_task_flop_filters(filters) do
    filters
    |> Enum.map(fn filter ->
      "outcome" = filter.id
      %{filter | value: if(filter.value, do: Atom.to_string(filter.value))}
    end)
    |> Filter.Operations.convert_filters_to_flop()
  end

  defp ensure_allowed_cacheable_sort_by(value) when value in ["duration_ms", "cache_artifact_size"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_cacheable_sort_by(_), do: :duration_ms

  def sort_order_patch_value(category, current_category, current_order) do
    if category == current_category do
      if current_order == "asc", do: "desc", else: "asc"
    else
      "asc"
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

  defp cache_miss_reason(%{remote_cache_miss: true, remote_cache_stored: true}) do
    dgettext("dashboard_gradle", "No remote entry, then stored")
  end

  defp cache_miss_reason(%{remote_cache_miss: true}) do
    dgettext("dashboard_gradle", "No remote entry")
  end

  defp cache_miss_reason(_task), do: dgettext("dashboard_gradle", "—")

  defp configuration_cache_status_label("reused"), do: dgettext("dashboard_gradle", "Reused")
  defp configuration_cache_status_label("valid"), do: dgettext("dashboard_gradle", "Valid")
  defp configuration_cache_status_label("not_found"), do: dgettext("dashboard_gradle", "No entry")
  defp configuration_cache_status_label("partial"), do: dgettext("dashboard_gradle", "Partially invalid")
  defp configuration_cache_status_label("invalid"), do: dgettext("dashboard_gradle", "Invalid")
  defp configuration_cache_status_label(status), do: status

  defp configuration_phase_label("build"), do: dgettext("dashboard_gradle", "Build")
  defp configuration_phase_label("settings"), do: dgettext("dashboard_gradle", "Settings")
  defp configuration_phase_label("project"), do: dgettext("dashboard_gradle", "Project")
  defp configuration_phase_label(phase), do: phase

  defp format_duration(duration_ms) do
    DateFormatter.format_duration_from_milliseconds(duration_ms)
  end

  defp started_after(task, build_started_at) do
    if task.started_at && build_started_at do
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
