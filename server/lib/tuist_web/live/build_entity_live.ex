defmodule TuistWeb.BuildEntityLive do
  @moduledoc false

  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.AsyncCard
  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge, only: [run_ran_by_badge_cell: 1]

  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.API.BuildEntityResources
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.BuildEntityLabels, as: Labels
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph

  @date_keys ~w(analytics-date-range analytics-start-date analytics-end-date)
  @duration_fields ~w(avg_duration_ms p50_duration_ms p90_duration_ms p99_duration_ms)
  @inventory_sort_fields ~w(name last_seen_at last_ran_at) ++ @duration_fields
  @activity_keys ~w(activity-search activity-sort activity-order filter_git_branch_op filter_git_branch_val filter_status_op filter_status_val)
  @removed_filter_keys ~w(filter_cache_status_op filter_cache_status_val)
  @query_keys @date_keys ++
                @activity_keys ++
                ~w(tab widget duration duration-chart-type duration-group-by environment branch q sort order page after before)

  def mount(_params, _session, socket) do
    resource = BuildEntityResources.fetch!(socket.assigns.live_action)
    project = socket.assigns.selected_project

    if resource.key == :mix_files or project.build_system != resource.system or not BuildEntities.enabled?(project) do
      raise NotFoundError, dgettext("dashboard_builds", "Not found in this project.")
    end

    {:ok,
     socket
     |> assign(:resource, resource)
     |> assign(:available_filters, [])
     |> assign(:entity_id, nil)
     |> assign(:entity, nil)
     |> assign(:analytics, AsyncResult.loading())
     |> assign(:module_inventory, AsyncResult.loading())
     |> assign(:duration_scatter, AsyncResult.loading())
     |> assign(:entries, AsyncResult.loading())
     |> assign(:history, AsyncResult.loading())}
  end

  def handle_params(params, uri, socket) do
    resource = socket.assigns.resource
    project = socket.assigns.selected_project
    id = params[to_string(resource.id_param)]
    params = Map.drop(params, @removed_filter_keys)

    params =
      if id,
        do: params,
        else: Map.drop(params, ~w(branch) ++ Enum.filter(@activity_keys, &String.starts_with?(&1, "filter_")))

    available_filters = if id, do: define_filters(resource), else: []

    %{
      durations?: durations?,
      widget: widget,
      inventory_sort: inventory_sort,
      duration_field: duration_field,
      sort_by: sort_by
    } =
      display_options(params, resource, id)

    entity_changed? = socket.assigns.entity_id != id

    entity = entity_for_page(project, resource, socket, id, entity_changed?)

    date_params = Map.take(params, @date_keys)
    %{preset: preset, period: new_period} = DatePicker.date_picker_params(params, "analytics")

    period =
      if socket.assigns[:date_params] == date_params,
        do: socket.assigns.period,
        else: bounded_period(new_period)

    {start_at, end_at} = period
    environment = selection(params, "environment", ~w(ci local), "any")
    tab = selection(params, "tab", ~w(history), "overview")
    page = page(params["page"])
    sort_order = selection(params, "activity-order", ~w(asc), "desc")
    active_filters = active_filters(params, available_filters)

    opts =
      [
        start_datetime: start_at,
        end_datetime: end_at,
        environment: environment,
        branch: params["branch"],
        page: page,
        page_size: 20,
        after: params["after"],
        before: params["before"]
      ] ++ table_options(id, params, active_filters, sort_by, sort_order, inventory_sort)

    title = if entity, do: entity.name, else: Labels.plural(resource.system, resource.kind)
    path = URI.parse(uri).path

    socket =
      socket
      |> reset_identity(entity_changed?)
      |> assign(:entity_id, id)
      |> assign(:entity, entity)
      |> assign(:params, Map.take(params, @query_keys))
      |> assign(:path, path)
      |> assign(:uri, %{URI.parse(uri) | query: URI.encode_query(Map.take(params, @query_keys))})
      |> assign(:period, period)
      |> assign(:date_params, date_params)
      |> assign(:preset, preset)
      |> assign(:analytics_trend_label, analytics_trend_label(preset))
      |> assign(:environment, environment)
      |> assign(:branch, params["branch"] || "")
      |> assign(:search, params["q"] || "")
      |> assign(:activity_search, params["activity-search"] || "")
      |> assign(:inventory_sort_by, inventory_sort)
      |> assign(:durations?, durations?)
      |> assign(:available_filters, available_filters)
      |> assign(:inventory_sort_order, selection(params, "order", ~w(asc), "desc"))
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign(:active_filters, active_filters)
      |> assign(:tab, tab)
      |> assign(:widget, widget)
      |> assign(:duration_field, duration_field)
      |> assign(:duration_chart_type, duration_chart_type(params, id))
      |> assign(
        :duration_group_by,
        selection(params, "duration-group-by", ~w(environment), "status")
      )
      |> assign(:page, page)
      |> assign(:head_title, "#{title} · Builds · Tuist")
      |> assign(
        OpenGraph.project_image_assigns(project, title: title, subtitle: Labels.plural(resource.system, resource.kind))
      )

    socket =
      if connected?(socket) do
        load(socket, resource, project.id, id, opts, entity_changed?)
      else
        socket
      end

    {:noreply, socket}
  end

  defp display_options(params, resource, id) do
    durations? = Labels.durations?(resource.system, resource.kind)
    widgets = if id, do: [], else: ~w(failures entities)
    widgets = if durations?, do: ["duration" | widgets], else: widgets
    inventory_sorts = if durations?, do: @inventory_sort_fields, else: ~w(name last_ran_at)

    %{
      durations?: durations?,
      widget: selection(params, "widget", widgets, "observations"),
      inventory_sort:
        selection(params, "sort", inventory_sorts, if(durations?, do: "p90_duration_ms", else: "last_ran_at")),
      duration_field:
        selection(params, "duration", @duration_fields, if(id, do: "p90_duration_ms", else: "avg_duration_ms")),
      sort_by: selection(params, "activity-sort", if(durations?, do: ~w(duration_ms), else: []), "observed_at")
    }
  end

  defp active_filters(params, available_filters) do
    filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    if params["branch"] not in [nil, ""] and !Enum.any?(filters, &(&1.id == "git_branch")) do
      branch_filter = Enum.find(available_filters, &(&1.id == "git_branch"))
      [%{branch_filter | operator: :==, value: params["branch"]} | filters]
    else
      filters
    end
  end

  defp table_options(nil, params, _filters, _sort_by, _sort_order, inventory_sort),
    do: [
      execution_durations_only: true,
      search: params["q"] || "",
      sort_by: inventory_sort,
      sort_order: selection(params, "order", ~w(asc), "desc")
    ]

  defp table_options(_id, params, filters, sort_by, sort_order, _inventory_sort),
    do: [
      executions_only: true,
      search: params["activity-search"] || "",
      filters: Filter.Operations.convert_filters_to_flop(filters),
      sort_by: sort_by,
      sort_order: sort_order
    ]

  defp entity_for_page(_project, _resource, _socket, nil, _changed?), do: nil
  defp entity_for_page(_project, _resource, socket, _id, false), do: socket.assigns.entity

  defp entity_for_page(project, resource, _socket, id, true) do
    case BuildEntities.get(project.id, resource.system, resource.kind, id) do
      {:ok, entity} -> entity
      _ -> raise NotFoundError, dgettext("dashboard_builds", "Not found in this project.")
    end
  end

  defp selection(params, key, values, default) do
    value = params[key]
    if value in values, do: value, else: default
  end

  defp maybe_load_module_inventory(socket, %{system: :xcode}, project_id, opts, reset?) do
    branch = socket.assigns.selected_project.default_branch
    opts = Keyword.take(opts, [:start_datetime, :end_datetime])

    maybe_load(socket, :module_inventory, {project_id, branch, opts}, reset?, fn ->
      {:ok, %{module_inventory: BuildEntities.default_branch_module_counts(project_id, branch, opts)}}
    end)
  end

  defp maybe_load_module_inventory(socket, _resource, _project_id, _opts, _reset?), do: socket

  defp load(socket, resource, project_id, nil, opts, reset?) do
    analytics_opts =
      Keyword.take(opts, [:start_datetime, :end_datetime, :environment, :branch, :execution_durations_only])

    socket =
      maybe_load(socket, :analytics, {:inventory, resource.key, analytics_opts}, reset?, fn ->
        {:ok, %{analytics: BuildEntities.inventory_analytics(project_id, resource.system, resource.kind, analytics_opts)}}
      end)

    socket = maybe_load_module_inventory(socket, resource, project_id, analytics_opts, reset?)
    socket = maybe_load_duration_scatter(socket, resource, project_id, nil, analytics_opts, reset?)

    maybe_load(socket, :entries, {nil, opts}, reset?, fn ->
      {entries, meta} = BuildEntities.list(project_id, resource.system, resource.kind, opts)
      {:ok, %{entries: %{rows: entries, meta: meta}}}
    end)
  end

  defp load(socket, resource, project_id, id, opts, reset?) do
    analytics_opts = Keyword.drop(opts, [:page, :page_size, :search, :after, :before, :filters, :sort_by, :sort_order])
    analytics_key = {id, analytics_opts}

    socket =
      if socket.assigns.tab == "overview" do
        maybe_load(socket, :analytics, analytics_key, reset?, fn ->
          {:ok, %{analytics: BuildEntities.analytics(project_id, resource.system, resource.kind, id, analytics_opts)}}
        end)
      else
        socket
      end

    socket = maybe_load_duration_scatter(socket, resource, project_id, id, analytics_opts, reset?)

    history_opts =
      if socket.assigns.tab == "overview" do
        opts |> Keyword.drop([:after, :before]) |> Keyword.merge(page: 1, page_size: 5)
      else
        opts
      end

    maybe_load(socket, :history, {id, history_opts}, reset?, fn ->
      {entries, meta} = BuildEntities.history(project_id, resource.system, resource.kind, id, history_opts)

      rows = history_context(entries, resource, project_id)

      {:ok,
       %{
         history: %{
           rows: rows,
           meta: meta,
           cursor_order: history_opts[:sort_by] == "observed_at" and history_opts[:sort_order] == "desc",
           row_navigation: Enum.all?(rows, & &1.parent_available)
         }
       }}
    end)
  end

  defp duration_chart_type(params, _id), do: selection(params, "duration-chart-type", ~w(scatter), "line")

  defp maybe_load_duration_scatter(socket, resource, project_id, id, opts, reset?) do
    if socket.assigns.tab == "overview" and socket.assigns.widget == "duration" and
         socket.assigns.duration_chart_type == "scatter" do
      maybe_load(socket, :duration_scatter, {id, opts}, reset?, fn ->
        result = read_duration_scatter(project_id, resource, id, opts)
        period = {Keyword.fetch!(opts, :start_datetime), Keyword.fetch!(opts, :end_datetime)}
        {:ok, %{duration_scatter: Map.put(result, :period, period)}}
      end)
    else
      socket
    end
  end

  defp read_duration_scatter(project_id, resource, nil, opts),
    do: BuildEntities.inventory_duration_scatter(project_id, resource.system, resource.kind, opts)

  defp read_duration_scatter(project_id, resource, id, opts),
    do: BuildEntities.duration_scatter(project_id, resource.system, resource.kind, id, opts)

  defp history_context(rows, resource, project_id) do
    ids = rows |> Enum.map(& &1.parent_id) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
    contexts = parent_contexts(project_id, resource, ids)

    Enum.map(rows, fn row ->
      context = Map.get(contexts, row.parent_id, %{})

      row
      |> Map.merge(Map.take(context, [:submission_auth, :claimed_actor_id, :actor_account]))
      |> Map.merge(%{
        parent_available: row.parent_id != "",
        parent_label: context_label(resource, context),
        parent_tags: Map.get(context, :tags, []),
        ran_by_name: Map.get(context, :ran_by_name)
      })
    end)
  end

  defp parent_contexts(project_id, resource, ids) do
    BuildEntities.parent_contexts(project_id, resource.system, resource.kind, ids)
  rescue
    QueryLimitError -> %{}
  end

  defp context_label(_resource, %{label: label}) when label in [nil, ""], do: nil

  defp context_label(_resource, context), do: Map.get(context, :label)

  defp history_context_cell(assigns) do
    ~H"""
    <div title={@row.parent_id}>
      <.text_and_description_cell label={reported(@row.parent_label)} />
    </div>
    """
  end

  defp reset_identity(socket, false), do: socket

  defp reset_identity(socket, true) do
    socket
    |> cancel_async(:duration_scatter)
    |> assign(:load_keys, %{})
    |> assign(:analytics, AsyncResult.loading())
    |> assign(:duration_scatter, AsyncResult.loading())
    |> assign(:entries, AsyncResult.loading())
    |> assign(:history, AsyncResult.loading())
  end

  defp maybe_load(socket, assign_name, key, reset?, fun) do
    keys = socket.assigns[:load_keys] || %{}
    result = socket.assigns[assign_name]

    if Map.get(keys, assign_name) == key && (result.ok? || result.loading) && !result.failed do
      socket
    else
      socket
      |> assign(:load_keys, Map.put(keys, assign_name, key))
      |> assign_async(assign_name, fun, reset: reset?)
    end
  end

  def handle_event("select_widget", %{"widget" => widget}, socket)
      when widget in ~w(observations duration failures entities) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"widget" => widget}), replace: true)}
  end

  def handle_event("select_duration", %{"duration" => duration}, socket) when duration in @duration_fields do
    {:noreply,
     push_patch(socket, to: patch(socket.assigns, %{"duration" => duration, "widget" => "duration"}), replace: true)}
  end

  def handle_event("select_inventory_duration", %{"type" => type}, socket) when type in ~w(avg p50 p90 p99) do
    {:noreply,
     push_patch(socket,
       to: patch(socket.assigns, %{"duration" => "#{type}_duration_ms", "widget" => "duration"}),
       replace: true
     )}
  end

  def handle_event("select_duration_chart_type", %{"type" => type}, socket) when type in ~w(line scatter) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"duration-chart-type" => type}), replace: true)}
  end

  def handle_event("filters", params, socket) do
    values = params |> Map.take(~w(q branch)) |> Map.put("page", nil) |> Map.put("after", nil) |> Map.put("before", nil)
    {:noreply, push_patch(socket, to: patch(socket.assigns, values))}
  end

  def handle_event("search_activity", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, reset_pagination(%{"activity-search" => search})))}
  end

  def handle_event("add_filter", %{"value" => id}, socket) do
    if Enum.any?(socket.assigns.available_filters, &(&1.id == id)) do
      params = Filter.Operations.add_filter_to_query(id, socket, filter_params(socket.assigns, id))

      {:noreply,
       socket
       |> push_patch(to: query_path(socket.assigns.path, Map.drop(params, ~w(page after before))))
       |> push_event("open-dropdown", %{id: "filter-#{id}-value-dropdown"})
       |> push_event("open-popover", %{id: "filter-#{id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", params, socket) do
    query =
      Filter.Operations.update_filters_in_query(
        params,
        socket,
        filter_params(socket.assigns, params["payload_filter_id"])
      )

    {:noreply,
     socket
     |> push_patch(to: query_path(socket.assigns.path, Map.drop(query, ~w(page after before))))
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event("analytics_period_changed", %{"value" => value, "preset" => preset}, socket) do
    values =
      if preset == "custom" do
        %{
          "analytics-date-range" => preset,
          "analytics-start-date" => value["start"],
          "analytics-end-date" => value["end"]
        }
      else
        %{"analytics-date-range" => preset, "analytics-start-date" => nil, "analytics-end-date" => nil}
      end

    {:noreply, push_patch(socket, to: patch(socket.assigns, reset_pagination(values)))}
  end

  defp filter_params(assigns, filter_id) do
    params = if filter_id == "git_branch", do: Map.delete(assigns.params, "branch"), else: assigns.params
    Map.merge(params, Filter.Operations.encode_filters_to_query(assigns.active_filters))
  end

  defp reset_pagination(changes), do: Map.merge(changes, %{"page" => nil, "after" => nil, "before" => nil})

  defp sort_patch(assigns, field) do
    order = if assigns.sort_by == field and assigns.sort_order == "desc", do: "asc", else: "desc"
    patch(assigns, reset_pagination(%{"activity-sort" => field, "activity-order" => order}))
  end

  defp inventory_sort_patch(assigns, field) do
    order = if assigns.inventory_sort_by == field and assigns.inventory_sort_order == "desc", do: "asc", else: "desc"
    patch(assigns, reset_pagination(%{"sort" => field, "order" => order}))
  end

  defp inventory_sort_options(assigns) do
    [{"name", Labels.singular(assigns.resource.system, assigns.resource.kind)}] ++
      inventory_duration_sort_options(assigns) ++ [{"last_ran_at", dgettext("dashboard_builds", "Last ran at")}]
  end

  defp inventory_duration_sort_options(%{durations?: false}), do: []

  defp inventory_duration_sort_options(_assigns) do
    [
      {"p50_duration_ms", "p50"},
      {"p90_duration_ms", "p90"},
      {"p99_duration_ms", "p99"},
      {"avg_duration_ms", dgettext("dashboard_builds", "Avg.")}
    ]
  end

  defp cursor_order?(assigns), do: assigns.history.result.cursor_order

  defp history_page_patch(assigns, direction) do
    meta = assigns.history.result.meta

    if cursor_order?(assigns) do
      changes = if direction == :next, do: %{"after" => meta.after}, else: %{"before" => meta.before}
      patch(assigns, Map.merge(reset_pagination(%{}), changes))
    else
      page = meta.current_page + if(direction == :next, do: 1, else: -1)
      patch(assigns, %{"page" => page, "after" => nil, "before" => nil})
    end
  end

  defp define_filters(resource) do
    statuses =
      case resource.system do
        :xcode -> ~w(success failure unknown)
        :mix -> ~w(success unknown)
        _ -> ~w(success failure)
      end

    [
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: dgettext("dashboard_builds", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_builds", "Status"),
        type: :option,
        operator: :==,
        options: statuses,
        options_display_names: %{
          "success" => dgettext("dashboard_builds", "Passed"),
          "failure" => dgettext("dashboard_builds", "Failed"),
          "unknown" => dgettext("dashboard_builds", "Not recorded")
        }
      }
    ]
  end

  defp patch(assigns, changes), do: query_path(assigns.path, Map.merge(assigns.params, changes))

  defp query_path(path, params) do
    query = Map.reject(params, fn {_key, value} -> value in [nil, ""] end)
    path <> if(map_size(query) > 0, do: "?" <> URI.encode_query(query), else: "")
  end

  defp project_path(assigns), do: "/#{assigns.selected_project.account.name}/#{assigns.selected_project.name}"
  defp inventory_path(assigns), do: project_path(assigns) <> assigns.resource.path

  defp navigation_path(assigns, path), do: query_path(path, Map.drop(assigns.params, ~w(tab page after before)))
  defp list_path(assigns), do: navigation_path(assigns, inventory_path(assigns))

  defp entity_path(assigns, entity),
    do: navigation_path(assigns, inventory_path(assigns) <> "/" <> URI.encode(entity.id, &URI.char_unreserved?/1))

  defp execution_path(assigns, row) do
    root = "/#{assigns.selected_project.account.name}/#{assigns.selected_project.name}"
    parent = URI.encode(row.parent_id, &URI.char_unreserved?/1)

    case assigns.resource.system do
      :gradle when row.execution_id != "" ->
        root <> "/builds/build-runs/#{parent}/tasks/#{row.execution_id}"

      :once ->
        root <> "/once/runs/#{parent}"

      :bazel ->
        root <> "/builds/invocations/#{URI.encode(parent, &URI.char_unreserved?/1)}"

      :mix ->
        root <> "/builds/mix-builds/#{parent}"

      :xcode when assigns.resource.kind == "module" ->
        if String.starts_with?(row.execution_id, "build_target:"),
          do: root <> "/builds/build-runs/#{parent}",
          else: root <> "/runs/#{parent}?tab=module-cache"

      _ ->
        root <> "/builds/build-runs/#{parent}"
    end
  end

  defp page(value) do
    case Integer.parse(to_string(value || "1")) do
      {number, ""} when number > 0 and number <= 10_000 -> number
      _ -> 1
    end
  end

  defp bounded_period({start_at, end_at}) do
    now = DateTime.utc_now()
    lower = DateTime.add(now, -90, :day)
    end_at = DateTime.add(end_at, 1, :second)
    end_at = if DateTime.after?(end_at, now), do: now, else: end_at
    start_at = if DateTime.before?(start_at, lower), do: lower, else: start_at
    if DateTime.before?(start_at, end_at), do: {start_at, end_at}, else: {DateTime.add(now, -30, :day), now}
  end

  defp duration(nil), do: dgettext("dashboard_builds", "Not recorded")
  defp duration(value), do: DateFormatter.format_duration_from_milliseconds(round(value))

  defp relative_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> DateFormatter.from_now(datetime)
      _ -> value
    end
  end

  defp relative_time(value), do: DateFormatter.from_now(value)

  defp identity_label("target_label"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("mnemonic"), do: dgettext("dashboard_builds", "Action type")
  defp identity_label("primary_output"), do: dgettext("dashboard_builds", "Primary output")
  defp identity_label("root_project_name"), do: dgettext("dashboard_builds", "Root project")
  defp identity_label("build_path"), do: dgettext("dashboard_builds", "Build path")
  defp identity_label("task_path"), do: dgettext("dashboard_builds", "Task path")
  defp identity_label("task_type"), do: dgettext("dashboard_builds", "Task type")
  defp identity_label("target"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("project"), do: dgettext("dashboard_builds", "Project")
  defp identity_label("target_id"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("target_name"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("project_name"), do: dgettext("dashboard_builds", "Project")
  defp identity_label("xcode_project_name"), do: dgettext("dashboard_builds", "Project")
  defp identity_label("capability"), do: dgettext("dashboard_builds", "Capability")
  defp identity_label("action_index"), do: dgettext("dashboard_builds", "Declared action index")
  defp identity_label("path"), do: dgettext("dashboard_builds", "Path")
  defp identity_label("module"), do: dgettext("dashboard_builds", "Module")
  defp identity_label(key), do: key

  defp observations_label(assigns) do
    case {assigns.resource.system, assigns.resource.kind} do
      {:mix, _} -> dgettext("dashboard_builds", "Compilations")
      {:xcode, "module"} -> dgettext("dashboard_builds", "Module builds")
      _ -> dgettext("dashboard_builds", "Executions")
    end
  end

  defp trend(current, previous) when is_number(current) and is_number(previous) and previous > 0,
    do: (current - previous) / previous * 100

  defp trend(current, previous) when is_number(current) and previous == 0, do: current * 1.0
  defp trend(_current, _previous), do: nil

  defp trend_value_label(current, previous, metric) when is_number(current) and current > 0 and previous == 0 do
    value = if metric == :duration, do: duration(current), else: format_number(current)
    "+#{value}"
  end

  defp trend_value_label(_current, _previous, _metric), do: nil

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_builds", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_builds", "since last week")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_builds", "since last period")
  defp analytics_trend_label(_preset), do: dgettext("dashboard_builds", "since last month")

  defp default_branch_module_widget(assigns) do
    result = assigns.module_inventory
    current = if result.ok?, do: result.result.total
    previous = if result.ok?, do: result.result.previous

    assigns =
      assigns
      |> assign(:ready, result.ok? || result.failed)
      |> assign(:current_count, current)
      |> assign(:previous_count, previous)

    ~H"""
    <.widget
      id="inventory-entities"
      loading={!@ready}
      title={dgettext("dashboard_builds", "Modules")}
      description={
        dgettext(
          "dashboard_builds",
          "Latest recorded module count from a generated-project graph on the default branch (%{branch}) before the end of the selected period, independent of environment. The chart carries that reported count forward until another scoped snapshot arrives. Historical graphs without scoped count metadata remain unavailable.",
          branch: @selected_project.default_branch || dgettext("dashboard_builds", "Not configured")
        )
      }
      value={if is_number(@current_count), do: format_number(@current_count)}
      empty={@ready && is_nil(@current_count)}
      empty_label={
        if @module_inventory.failed,
          do: dgettext("dashboard_builds", "Unavailable"),
          else: dgettext("dashboard_builds", "Not recorded")
      }
      selected={@widget == "entities"}
      legend_color="p99"
      phx_click="select_widget"
      phx_value_widget="entities"
      trend_value={trend(@current_count, @previous_count)}
      trend_value_label={trend_value_label(@current_count, @previous_count, :count)}
      trend_type={:neutral}
      trend_label={@analytics_trend_label}
    />
    """
  end

  defp default_branch_module_chart(assigns) do
    ~H"""
    <.async_section :let={ready?} results={[@module_inventory]}>
      <.skeleton_box :if={!ready?} width="100%" height="200px" />
      <.chart
        :if={ready? && is_number(@module_inventory.result.total)}
        id="build-entity-inventory-chart"
        type="line"
        series={chart_series(assigns, @module_inventory.result.points)}
        extra_options={chart_options(assigns)}
        y_axis_min={0}
      />
      <.empty_card_section
        :if={ready? && is_nil(@module_inventory.result.total)}
        title={dgettext("dashboard_builds", "No reported default-branch graph")}
      >
        <:image>
          <img src={~p"/images/empty_line_chart_light.png"} data-theme="light" loading="lazy" />
          <img src={~p"/images/empty_line_chart_dark.png"} data-theme="dark" loading="lazy" />
        </:image>
      </.empty_card_section>
    </.async_section>
    """
  end

  defp inventory_count_widget(assigns) do
    field = inventory_count_field(assigns, assigns.metric)
    value = if assigns.ready, do: inventory_count_value(assigns.analytics.result.total, field)
    previous = if assigns.ready, do: inventory_count_value(assigns.analytics.result.previous, field)
    no_data? = assigns.ready && assigns.analytics.result.total.observations == 0

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:empty, assigns.ready && (no_data? or is_nil(value)))
      |> assign(
        :empty_label,
        if(no_data?, do: dgettext("dashboard_builds", "No data"), else: dgettext("dashboard_builds", "Not recorded"))
      )
      |> assign(:trend_value, trend(value, previous))
      |> assign(:trend_value_label, trend_value_label(value, previous, :count))
      |> assign(
        :legend_color,
        Map.fetch!(%{observations: "primary", failures: "destructive", entities: "p99"}, assigns.metric)
      )

    ~H"""
    <.widget
      id={"inventory-#{@metric}"}
      loading={!@ready}
      title={inventory_count_label(assigns, @metric)}
      description={inventory_count_description(assigns, @metric)}
      value={if is_number(@value), do: format_number(@value)}
      empty={@empty}
      empty_label={@empty_label}
      selected={@widget == to_string(@metric)}
      legend_color={@legend_color}
      phx_click="select_widget"
      phx_value_widget={to_string(@metric)}
      trend_value={@trend_value}
      trend_value_label={@trend_value_label}
      trend_type={if @metric == :failures, do: :inverse, else: :neutral}
      trend_label={@analytics_trend_label}
    />
    """
  end

  defp inventory_count_field(%{entity: nil, resource: %{system: :xcode}}, :observations), do: :duration_samples

  defp inventory_count_field(%{entity: nil, resource: %{system: system}}, :observations)
       when system in [:gradle, :once, :bazel], do: :executions

  defp inventory_count_field(_assigns, metric), do: metric

  defp inventory_count_value(%{outcome_samples: 0}, :failures), do: nil
  defp inventory_count_value(metrics, metric), do: Map.fetch!(metrics, metric)

  defp inventory_count_label(assigns, :entities), do: Labels.plural(assigns.resource.system, assigns.resource.kind)

  defp inventory_count_label(assigns, :observations) do
    case {assigns.resource.system, assigns.resource.kind} do
      {:xcode, _} -> dgettext("dashboard_builds", "Module builds")
      {:gradle, _} -> dgettext("dashboard_builds", "Task executions")
      {system, _} when system in [:once, :bazel] -> dgettext("dashboard_builds", "Action executions")
      {:mix, "file"} -> dgettext("dashboard_builds", "File compilations")
      {:mix, "module"} -> dgettext("dashboard_builds", "Module compilations")
    end
  end

  defp inventory_count_label(assigns, :failures) do
    case assigns.resource.system do
      :xcode -> dgettext("dashboard_builds", "Failed module builds")
      :gradle -> dgettext("dashboard_builds", "Failed task executions")
      system when system in [:once, :bazel] -> dgettext("dashboard_builds", "Failed action executions")
      _ -> dgettext("dashboard_builds", "Failed compilations")
    end
  end

  defp inventory_count_description(%{resource: %{system: :xcode}}, :observations),
    do:
      dgettext(
        "dashboard_builds",
        "Module builds with recorded compilation work during the selected period. Module-cache resolutions and modules without compilation work are excluded."
      )

  defp inventory_count_description(%{resource: %{system: :bazel}}, :observations),
    do:
      dgettext(
        "dashboard_builds",
        "BEP-reported action executions, not cache lookups. Reporting must publish all actions for complete execution coverage; missing timing remains unavailable."
      )

  defp inventory_count_description(%{resource: %{system: :gradle}}, :observations),
    do:
      dgettext(
        "dashboard_builds",
        "Task executions with a recorded success or failure. Cache hits, skipped, up-to-date and no-source tasks are excluded, regardless of timing availability."
      )

  defp inventory_count_description(%{resource: %{system: :once}}, :observations),
    do:
      dgettext(
        "dashboard_builds",
        "Uncached action executions with a recorded success or failure. Cached, skipped, cancelled and unknown outcomes are excluded, regardless of timing availability."
      )

  defp inventory_count_description(%{resource: %{system: :mix, kind: "file"}}, :observations),
    do: dgettext("dashboard_builds", "Reported file compilations, including those without a measured duration.")

  defp inventory_count_description(%{resource: %{system: :mix, kind: "module"}}, :observations),
    do:
      dgettext(
        "dashboard_builds",
        "Module compilation records derived from compiled files, including those without measured timing. A file defining multiple modules contributes one record per module, not independent compilation work."
      )

  defp inventory_count_description(%{resource: %{system: :xcode}}, :failures),
    do:
      dgettext(
        "dashboard_builds",
        "Recorded module build failures during the selected period. Unknown outcomes are not counted as successes or failures."
      )

  defp inventory_count_description(assigns, :failures) do
    case assigns.resource.kind do
      "task" ->
        dgettext(
          "dashboard_builds",
          "Recorded task execution failures during the selected period. Unknown outcomes are not counted as successes or failures."
        )

      "action" ->
        dgettext(
          "dashboard_builds",
          "Recorded action execution failures during the selected period. Unknown outcomes are not counted as successes or failures."
        )

      "file" ->
        dgettext(
          "dashboard_builds",
          "Recorded file compilation failures during the selected period. Unknown outcomes are not counted as successes or failures."
        )

      "module" ->
        dgettext(
          "dashboard_builds",
          "Recorded module compilation failures during the selected period. Unknown outcomes are not counted as successes or failures."
        )
    end
  end

  defp inventory_count_description(assigns, :entities) do
    case assigns.resource.kind do
      "task" ->
        dgettext(
          "dashboard_builds",
          "Distinct tasks with recorded activity during the selected period. The chart shows distinct tasks per day, not a cumulative total."
        )

      "action" ->
        dgettext(
          "dashboard_builds",
          "Distinct actions with recorded activity during the selected period. The chart shows distinct actions per day, not a cumulative total."
        )

      "file" ->
        dgettext(
          "dashboard_builds",
          "Distinct files with recorded activity during the selected period. The chart shows distinct files per day, not a cumulative total."
        )

      "module" ->
        dgettext(
          "dashboard_builds",
          "Distinct modules with recorded activity during the selected period. The chart shows distinct modules per day, not a cumulative total."
        )
    end
  end

  defp inventory_duration_title(assigns) do
    type = String.replace_suffix(assigns.duration_field, "_duration_ms", "")
    percentile = if type == "avg", do: dgettext("dashboard_builds", "Avg."), else: type

    case {assigns.resource.system, assigns.resource.kind} do
      {:mix, "module"} ->
        dgettext("dashboard_builds", "%{percentile} file compilation duration", percentile: percentile)

      {:xcode, "module"} ->
        dgettext("dashboard_builds", "%{percentile} module build duration", percentile: percentile)

      {:mix, "file"} ->
        dgettext("dashboard_builds", "%{percentile} compilation duration", percentile: percentile)

      _ ->
        dgettext("dashboard_builds", "%{percentile} execution duration", percentile: percentile)
    end
  end

  defp inventory_duration_description(%{resource: %{system: :xcode}}),
    do:
      dgettext(
        "dashboard_builds",
        "Measured compilation time for module builds, not total build time. Cache resolutions and modules without compilation work do not contribute timing samples."
      )

  defp inventory_duration_description(%{resource: %{system: :mix, kind: "module"}}),
    do:
      dgettext(
        "dashboard_builds",
        "Each module contributes its containing file's measured compilation duration. Sibling modules share that measurement; their durations are not additive."
      )

  defp inventory_duration_description(%{resource: %{kind: "task"}}),
    do:
      dgettext(
        "dashboard_builds",
        "Measured task durations during the selected period. Missing measurements are excluded; genuine measured zeros are included."
      )

  defp inventory_duration_description(%{resource: %{kind: "action"}}),
    do:
      dgettext(
        "dashboard_builds",
        "Measured action durations during the selected period. Missing measurements are excluded; genuine measured zeros are included."
      )

  defp inventory_duration_description(%{resource: %{system: :mix, kind: "file"}}),
    do:
      dgettext(
        "dashboard_builds",
        "Measured file compilation durations during the selected period. Missing measurements are excluded; genuine measured zeros are included."
      )

  defp inventory_duration_metrics(metrics) do
    Map.new([:avg, :p50, :p90, :p99], fn type ->
      {type, duration(Map.fetch!(metrics, String.to_existing_atom("#{type}_duration_ms")))}
    end)
  end

  defp duration_scatter_plot(assigns) do
    ~H"""
    <.async_section :let={ready?} results={[@duration_scatter]}>
      <.skeleton_box :if={!ready?} width="100%" height={@height} />
      <.scatter_chart
        :if={ready? && @duration_scatter.result.rows != []}
        id={@chart_id}
        chart={scatter_chart_result(assigns)}
        period={@duration_scatter.result.period}
        value_format="fn:formatMilliseconds"
        truncation_title={
          dgettext(
            "dashboard_builds",
            "Showing the latest 10,000 measured durations since %{date}. Narrow the period or environment to see other observations.",
            date: scatter_oldest_entry_formatted({:scatter, @duration_scatter.result})
          )
        }
      />
      <.empty_card_section
        :if={ready? && @duration_scatter.result.rows == []}
        title={dgettext("dashboard_builds", "No recorded durations")}
      >
        <:image>
          <img src={~p"/images/empty_line_chart_light.png"} data-theme="light" loading="lazy" />
          <img src={~p"/images/empty_line_chart_dark.png"} data-theme="dark" loading="lazy" />
        </:image>
      </.empty_card_section>
    </.async_section>
    """
  end

  defp controls(assigns) do
    ~H"""
    <div data-part="analytics-controls">
      <.dropdown
        id={"entity-environment-#{@tab}"}
        label={Labels.environment(@environment)}
        secondary_text={dgettext("dashboard_builds", "Environment:")}
      >
        <.dropdown_item
          :for={value <- ~w(any ci local)}
          value={value}
          label={Labels.environment(value)}
          patch={
            patch(assigns, %{"environment" => value, "page" => nil, "after" => nil, "before" => nil})
          }
          data-selected={@environment == value}
        >
          <:right_icon><.check /></:right_icon>
        </.dropdown_item>
      </.dropdown>
      <.date_picker
        id="entity-period"
        name="analytics-date-range"
        presets={[
          %{
            id: "last-24-hours",
            label: dgettext("dashboard_builds", "Last 24 hours"),
            period: {24, :hour}
          },
          %{id: "last-7-days", label: dgettext("dashboard_builds", "Last 7 days"), period: {7, :day}},
          %{
            id: "last-30-days",
            label: dgettext("dashboard_builds", "Last 30 days"),
            period: {30, :day}
          },
          %{id: "custom", label: dgettext("dashboard_builds", "Custom")}
        ]}
        selected_preset={@preset}
        period={@period}
        on_period_change="analytics_period_changed"
        min={Date.add(Date.utc_today(), -90)}
        max={Date.utc_today()}
      >
        <:actions>
          <.button
            label={dgettext("dashboard_builds", "Cancel")}
            variant="secondary"
            phx-click={JS.dispatch("phx:date-picker-cancel", detail: %{id: "entity-period"})}
          />
          <.button
            label={dgettext("dashboard_builds", "Apply")}
            phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "entity-period"})}
          />
        </:actions>
      </.date_picker>
    </div>
    """
  end

  defp default_branch_chart?(assigns),
    do: is_nil(assigns.entity) and assigns.resource.system == :xcode and assigns.widget == "entities"

  defp chart_available?(assigns) do
    total = assigns.analytics.result.total

    case assigns.widget do
      "duration" -> total.duration_samples > 0
      "failures" -> total.outcome_samples > 0
      _ -> total.observations > 0
    end
  end

  defp empty_chart_title(%{analytics: %{result: %{total: %{observations: 0}}}}),
    do: dgettext("dashboard_builds", "No data in this period")

  defp empty_chart_title(%{widget: "duration"}), do: dgettext("dashboard_builds", "No recorded durations")
  defp empty_chart_title(%{widget: "failures"}), do: dgettext("dashboard_builds", "No recorded outcomes")
  defp empty_chart_title(_assigns), do: dgettext("dashboard_builds", "No data in this period")

  defp chart_series(assigns, points) do
    fields =
      case assigns.widget do
        "duration" ->
          [
            {:avg_duration_ms, dgettext("dashboard_builds", "Average"), "secondary"},
            {:p50_duration_ms, "p50", "p50"},
            {:p90_duration_ms, "p90", "p90"},
            {:p99_duration_ms, "p99", "p99"}
          ]

        "failures" ->
          [{:failures, inventory_count_label(assigns, :failures), "destructive"}]

        "entities" ->
          [{:entities, Labels.plural(assigns.resource.system, assigns.resource.kind), "p99"}]

        _ ->
          label = if assigns.entity, do: observations_label(assigns), else: inventory_count_label(assigns, :observations)
          [{inventory_count_field(assigns, :observations), label, "primary"}]
      end

    Enum.map(fields, fn {field, name, color} ->
      %{
        name: name,
        type: chart_type(assigns),
        color: "var:noora-chart-#{color}",
        data: Enum.map(points, &chart_point(&1, field, name)),
        connectNulls: false,
        smooth: if(default_branch_chart?(assigns), do: false, else: 0.1),
        step: if(default_branch_chart?(assigns), do: "end", else: false),
        symbol: "circle",
        symbolSize: 4,
        showAllSymbol: true
      }
    end)
  end

  defp chart_type(%{entity: nil}), do: "line"
  defp chart_type(%{widget: "observations"}), do: "bar"
  defp chart_type(_assigns), do: "line"

  defp chart_point(point, :failures, _name) do
    value = if point.observations > 0 and point.outcome_samples == 0, do: nil, else: point.failures
    [point.date, value]
  end

  defp chart_point(point, :avg_duration_ms, name) do
    %{
      value: [point.date, point.avg_duration_ms],
      tooltipExtra: [
        %{label: name, value: duration(point.avg_duration_ms)},
        %{label: dgettext("dashboard_builds", "Measured durations"), value: format_number(point.duration_samples)}
      ]
    }
  end

  defp chart_point(point, field, _name), do: [point.date, Map.get(point, field)]

  defp duration_group_options do
    [
      %{value: "status", label: dgettext("dashboard_builds", "Status")},
      %{value: "environment", label: dgettext("dashboard_builds", "Environment")}
    ]
  end

  defp scatter_chart_result(%{duration_scatter: %{ok?: false} = result}), do: result

  defp scatter_chart_result(assigns) do
    result = assigns.duration_scatter

    series =
      result.result.rows
      |> Enum.group_by(&scatter_group(&1, assigns.duration_group_by))
      |> Enum.sort_by(fn {group, _rows} -> to_string(group) end)
      |> Enum.map(fn {group, rows} ->
        %{
          name: scatter_group_label(group, assigns.duration_group_by),
          color: scatter_group_color(group),
          data: Enum.map(rows, &scatter_point(&1, assigns))
        }
      end)

    data = result.result |> Map.take([:truncated, :oldest_entry]) |> Map.put(:series, series)
    %{result | result: {:scatter, data}}
  end

  defp scatter_group(row, "environment"), do: row.is_ci
  defp scatter_group(row, _group), do: row.status

  defp scatter_group_label(true, "environment"), do: Labels.environment("ci")
  defp scatter_group_label(false, "environment"), do: Labels.environment("local")
  defp scatter_group_label(_group, "environment"), do: dgettext("dashboard_builds", "Not reported")
  defp scatter_group_label("none", _dimension), do: dgettext("dashboard_builds", "Not reported")
  defp scatter_group_label(group, _dimension), do: execution_status_label(group)

  defp execution_status_label("success"), do: dgettext("dashboard_builds", "Passed")
  defp execution_status_label("failure"), do: dgettext("dashboard_builds", "Failed")
  defp execution_status_label(_status), do: dgettext("dashboard_builds", "Not recorded")

  defp scatter_group_color(group) do
    color =
      Map.get(
        %{
          "failure" => "destructive",
          "success" => "p99",
          true => "primary",
          false => "secondary"
        },
        group
      )

    if color, do: "var:noora-chart-#{color}", else: "var:noora-surface-label-secondary"
  end

  defp scatter_point(row, assigns) do
    %{
      id: row.id,
      value: [DateTime.to_unix(row.observed_at, :millisecond), row.duration_ms],
      url: scatter_point_path(assigns, row),
      tooltipExtra:
        scatter_identity_fields(assigns, row) ++
          [
            %{label: dgettext("dashboard_builds", "Status"), value: execution_status_label(row.status)},
            %{label: dgettext("dashboard_builds", "Environment"), value: scatter_group_label(row.is_ci, "environment")},
            %{
              label: dgettext("dashboard_builds", "Recorded at"),
              value: DateFormatter.format_with_timezone_short(row.observed_at, assigns.user_timezone)
            },
            %{label: dgettext("dashboard_builds", "Branch"), value: reported(row.git_branch)},
            %{label: dgettext("dashboard_builds", "Commit"), value: reported(row.git_commit_sha)}
          ]
    }
  end

  defp scatter_identity_fields(%{entity: nil} = assigns, row) do
    [
      %{label: Labels.singular(assigns.resource.system, assigns.resource.kind), value: row.name}
      | assigns.resource.system
        |> Labels.visible_identity(assigns.resource.kind, row.identity)
        |> Enum.sort()
        |> Enum.reject(fn {_key, value} -> value == row.name end)
        |> Enum.map(fn {key, _value} ->
          %{label: identity_label(key), value: Labels.identity_value(row.identity, key)}
        end)
    ]
  end

  defp scatter_identity_fields(_assigns, _row), do: []

  defp reported(value) when value in [nil, ""], do: dgettext("dashboard_builds", "Not reported")
  defp reported(value), do: value

  defp scatter_point_path(assigns, row) do
    if row.parent_id == "" do
      params =
        assigns.params
        |> Map.drop(@activity_keys)
        |> Map.merge(reset_pagination(%{"tab" => "history", "activity-search" => row.parent_id}))

      path = if assigns.entity, do: assigns.path, else: inventory_path(assigns) <> "/" <> row.entity_id
      query_path(path, params)
    else
      execution_path(assigns, row)
    end
  end

  defp chart_options(assigns) do
    formatter =
      case assigns.widget do
        "duration" -> "fn:formatMilliseconds"
        _ -> "{value}"
      end

    points =
      if default_branch_chart?(assigns), do: assigns.module_inventory.result.points, else: assigns.analytics.result.points

    dates = Enum.map(points, & &1.date)
    show_legend = assigns.widget == "duration"

    %{
      legend: %{
        show: show_legend,
        left: "left",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-secondary",
          fontFamily: "monospace",
          fontWeight: 400,
          fontSize: 10,
          lineHeight: 12
        },
        icon: "roundRect",
        itemWidth: 8,
        itemHeight: 4
      },
      grid: %{left: "0.4%", right: "3%", top: "5%", bottom: if(show_legend, do: "18%", else: "5%"), containLabel: true},
      xAxis: %{
        type: "category",
        boundaryGap: chart_type(assigns) == "bar",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
      },
      tooltip: %{valueFormat: formatter, dateFormat: if(assigns.preset == "last-24-hours", do: "hour", else: "date")}
    }
  end
end
