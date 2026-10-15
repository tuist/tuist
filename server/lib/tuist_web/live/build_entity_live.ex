defmodule TuistWeb.BuildEntityLive do
  @moduledoc false

  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.AsyncCard
  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.Runs.ProjectWithTags, only: [project_with_tags_cell: 1]
  import TuistWeb.Runs.RanByBadge, only: [run_ran_by_badge_cell: 1]

  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.API.BuildEntityResources
  alias TuistWeb.BazelAnalyticsHelpers
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.BuildEntityLabels, as: Labels
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Runs.CommandFormatter

  @date_keys ~w(analytics-date-range analytics-start-date analytics-end-date)
  @duration_fields ~w(avg_duration_ms p50_duration_ms p90_duration_ms p99_duration_ms)
  @activity_keys ~w(activity-search activity-sort activity-order filter_git_branch_op filter_git_branch_val filter_status_op filter_status_val filter_cache_status_op filter_cache_status_val)
  @query_keys @date_keys ++
                @activity_keys ++
                ~w(tab widget duration duration-chart-type duration-group-by environment branch q page after before)

  def mount(_params, _session, socket) do
    resource = BuildEntityResources.fetch!(socket.assigns.live_action)

    if socket.assigns.selected_project.build_system != resource.system do
      raise NotFoundError, dgettext("dashboard_builds", "Not found in this project.")
    end

    {:ok,
     socket
     |> assign(:resource, resource)
     |> assign(:available_filters, define_filters())
     |> assign(:entity_id, nil)
     |> assign(:entity, nil)
     |> assign(:analytics, AsyncResult.loading())
     |> assign(:duration_scatter, AsyncResult.loading())
     |> assign(:entries, AsyncResult.loading())
     |> assign(:history, AsyncResult.loading())}
  end

  def handle_params(params, uri, socket) do
    resource = socket.assigns.resource
    project = socket.assigns.selected_project
    id = params[to_string(resource.id_param)]
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
    widget = selection(params, "widget", ~w(hit_rate duration), "observations")
    duration_field = selection(params, "duration", @duration_fields, "p90_duration_ms")
    page = page(params["page"])
    sort_by = selection(params, "activity-sort", ~w(duration_ms), "observed_at")
    sort_order = selection(params, "activity-order", ~w(asc), "desc")
    active_filters = active_filters(params, socket.assigns.available_filters)

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
      ] ++ table_options(id, params, active_filters, sort_by, sort_order)

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
      |> assign(:environment, environment)
      |> assign(:branch, params["branch"] || "")
      |> assign(:search, params["q"] || "")
      |> assign(:activity_search, params["activity-search"] || "")
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign(:active_filters, active_filters)
      |> assign(:tab, tab)
      |> assign(:widget, widget)
      |> assign(:duration_field, duration_field)
      |> assign(:duration_chart_type, duration_chart_type(params, resource))
      |> assign(
        :duration_group_by,
        selection(params, "duration-group-by", ~w(environment), default_duration_group(resource))
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

  defp active_filters(params, available_filters) do
    filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    if params["branch"] not in [nil, ""] and !Enum.any?(filters, &(&1.id == "git_branch")) do
      branch_filter = Enum.find(available_filters, &(&1.id == "git_branch"))
      [%{branch_filter | operator: :==, value: params["branch"]} | filters]
    else
      filters
    end
  end

  defp table_options(nil, params, _filters, _sort_by, _sort_order),
    do: [search: params["q"] || "", sort_by: "last_seen_at", sort_order: "desc"]

  defp table_options(_id, params, filters, sort_by, sort_order),
    do: [
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

  defp load(socket, resource, project_id, nil, opts, reset?) do
    key = {nil, opts}

    maybe_load(socket, :entries, key, reset?, fn ->
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

  defp duration_supported?(%{system: :xcode, kind: "module"}), do: false
  defp duration_supported?(_resource), do: true

  defp duration_chart_type(params, %{system: :xcode, kind: "module"}),
    do: selection(params, "duration-chart-type", [], "line")

  defp duration_chart_type(params, _resource), do: selection(params, "duration-chart-type", ~w(scatter), "line")

  defp default_duration_group(%{kind: "cache_action"}), do: "cache_status"
  defp default_duration_group(_resource), do: "status"

  defp maybe_load_duration_scatter(socket, resource, project_id, id, opts, reset?) do
    if socket.assigns.tab == "overview" and socket.assigns.widget == "duration" and
         socket.assigns.duration_chart_type == "scatter" do
      maybe_load(socket, :duration_scatter, {id, opts}, reset?, fn ->
        result = BuildEntities.duration_scatter(project_id, resource.system, resource.kind, id, opts)
        period = {Keyword.fetch!(opts, :start_datetime), Keyword.fetch!(opts, :end_datetime)}
        {:ok, %{duration_scatter: Map.put(result, :period, period)}}
      end)
    else
      socket
    end
  end

  defp history_context(rows, resource, project_id) do
    ids = rows |> Enum.map(& &1.parent_id) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
    contexts = parent_contexts(project_id, resource, ids)

    Enum.map(rows, fn row ->
      context = Map.get(contexts, row.parent_id, %{})

      Map.merge(row, %{
        parent_available: row.parent_id != "" and (resource.system != :bazel or Map.has_key?(contexts, row.parent_id)),
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

  defp context_label(%{system: :xcode, kind: "module"}, %{label: label} = context) do
    CommandFormatter.format_command(%{name: label, command_arguments: Map.get(context, :command_arguments)})
  end

  defp context_label(%{system: :bazel}, %{label: label} = context) do
    BazelAnalyticsHelpers.requested_command(%{command: label, target_patterns: Map.get(context, :target_patterns, [])})
  end

  defp context_label(_resource, context), do: Map.get(context, :label)

  defp history_context_cell(assigns) do
    ~H"""
    <div title={@row.parent_id}>
      <.project_with_tags_cell
        :if={@resource.system == :gradle}
        label={reported(@row.parent_label)}
        tags={@row.parent_tags}
      />
      <.text_and_description_cell
        :if={@resource.system != :gradle}
        label={reported(@row.parent_label)}
      />
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

  def handle_event("select_widget", %{"widget" => widget}, socket) when widget in ~w(observations hit_rate duration) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"widget" => widget}), replace: true)}
  end

  def handle_event("select_duration", %{"duration" => duration}, socket) when duration in @duration_fields do
    {:noreply,
     push_patch(socket, to: patch(socket.assigns, %{"duration" => duration, "widget" => "duration"}), replace: true)}
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
      params = Filter.Operations.add_filter_to_query(id, socket, filter_params(socket.assigns))

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
    query = Filter.Operations.update_filters_in_query(params, socket, filter_params(socket.assigns))

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

  defp filter_params(assigns),
    do:
      assigns.params
      |> Map.delete("branch")
      |> Map.merge(Filter.Operations.encode_filters_to_query(assigns.active_filters))

  defp reset_pagination(changes), do: Map.merge(changes, %{"page" => nil, "after" => nil, "before" => nil})

  defp sort_patch(assigns, field) do
    order = if assigns.sort_by == field and assigns.sort_order == "desc", do: "asc", else: "desc"
    patch(assigns, reset_pagination(%{"activity-sort" => field, "activity-order" => order}))
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

  defp define_filters do
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
        display_name: dgettext("dashboard_builds", "Outcome"),
        type: :option,
        operator: :==,
        options: ~w(success failure skipped cancelled up_to_date no_source unknown),
        options_display_names:
          Map.new(~w(success failure skipped cancelled up_to_date no_source unknown), &{&1, Labels.status(&1)})
      },
      %Filter.Filter{
        id: "cache_status",
        field: :cache_status,
        display_name: dgettext("dashboard_builds", "Cache"),
        type: :option,
        operator: :==,
        options: ~w(hit hit_local hit_remote miss write none),
        options_display_names:
          Map.new(
            ~w(hit hit_local hit_remote miss write none),
            &{&1, if(&1 == "none", do: dgettext("dashboard_builds", "Not reported"), else: Labels.status(&1))}
          )
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

  defp gradle_rankings_path(assigns) do
    params =
      assigns.params
      |> Map.take(@date_keys ++ ["q"])
      |> Map.put("analytics-environment", assigns.environment)
      |> Map.put("filter_git_branch_op", if(assigns.branch != "", do: "=="))
      |> Map.put("filter_git_branch_val", assigns.branch)

    query_path(project_path(assigns) <> "/builds/tasks", params)
  end

  defp execution_path(assigns, row) do
    root = "/#{assigns.selected_project.account.name}/#{assigns.selected_project.name}"
    parent = URI.encode(row.parent_id, &URI.char_unreserved?/1)

    case assigns.resource.system do
      :gradle when row.execution_id != "" -> root <> "/builds/build-runs/#{parent}/tasks/#{row.execution_id}"
      :bazel -> root <> "/builds/invocations/#{parent}"
      :once -> root <> "/once/runs/#{parent}"
      :mix -> root <> "/builds/mix-builds/#{parent}"
      :xcode when assigns.resource.kind == "module" -> root <> "/runs/#{parent}?tab=module-cache"
      _ -> root <> "/builds/build-runs/#{parent}"
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
  defp percentage(nil), do: dgettext("dashboard_builds", "No recorded lookups")
  defp percentage(value), do: "#{Float.round(value * 1.0, 1)}%"

  defp relative_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> DateFormatter.from_now(datetime)
      _ -> value
    end
  end

  defp relative_time(value), do: DateFormatter.from_now(value)

  defp identity_label("root_project_name"), do: dgettext("dashboard_builds", "Root project")
  defp identity_label("build_path"), do: dgettext("dashboard_builds", "Build path")
  defp identity_label("task_path"), do: dgettext("dashboard_builds", "Task path")
  defp identity_label("task_type"), do: dgettext("dashboard_builds", "Task type")
  defp identity_label("target"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("project"), do: dgettext("dashboard_builds", "Project")
  defp identity_label("target_label"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("action_mnemonic"), do: dgettext("dashboard_builds", "Mnemonic")
  defp identity_label("target_id"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("target_name"), do: dgettext("dashboard_builds", "Target")
  defp identity_label("project_name"), do: dgettext("dashboard_builds", "Project")
  defp identity_label("xcode_project_name"), do: dgettext("dashboard_builds", "Project")
  defp identity_label("capability"), do: dgettext("dashboard_builds", "Capability")
  defp identity_label("action_index"), do: dgettext("dashboard_builds", "Declared action index")
  defp identity_label("key"), do: dgettext("dashboard_builds", "Cache key")
  defp identity_label("action_digest_hash"), do: dgettext("dashboard_builds", "Action digest hash")
  defp identity_label("configuration_id"), do: dgettext("dashboard_builds", "Configuration")
  defp identity_label("type"), do: dgettext("dashboard_builds", "Compiler")
  defp identity_label("path"), do: dgettext("dashboard_builds", "Path")
  defp identity_label("module"), do: dgettext("dashboard_builds", "Module")
  defp identity_label(key), do: key

  defp observations_label(assigns) do
    case {assigns.resource.system, assigns.resource.kind} do
      {:mix, _} -> dgettext("dashboard_builds", "Compilations")
      {_, "cache_action"} -> dgettext("dashboard_builds", "Cache operations")
      {:xcode, "module"} -> dgettext("dashboard_builds", "Cache lookups")
      _ -> dgettext("dashboard_builds", "Executions")
    end
  end

  defp trend(current, previous) when is_number(current) and is_number(previous) and previous > 0,
    do: (current - previous) / previous * 100

  defp trend(0, 0), do: 0.0
  defp trend(_current, _previous), do: nil

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

  defp chart_available?(assigns) do
    total = assigns.analytics.result.total

    case assigns.widget do
      "duration" -> total.duration_samples > 0
      "hit_rate" -> not is_nil(total.hit_rate)
      _ -> total.observations > 0
    end
  end

  defp empty_chart_title(%{analytics: %{result: %{total: %{observations: 0}}}}),
    do: dgettext("dashboard_builds", "No data in this period")

  defp empty_chart_title(%{widget: "duration"}), do: dgettext("dashboard_builds", "No recorded durations")
  defp empty_chart_title(_assigns), do: dgettext("dashboard_builds", "No recorded cache lookups")

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

        "hit_rate" ->
          [{:hit_rate, dgettext("dashboard_builds", "Cache hit rate"), "primary"}]

        _ ->
          [{:observations, observations_label(assigns), "primary"}]
      end

    Enum.map(fields, fn {field, name, color} ->
      %{
        name: name,
        type: if(assigns.widget == "observations", do: "bar", else: "line"),
        color: "var:noora-chart-#{color}",
        data: Enum.map(points, &chart_point(&1, field, name)),
        connectNulls: false,
        smooth: 0.1,
        symbol: "circle",
        symbolSize: 4,
        showAllSymbol: true
      }
    end)
  end

  defp chart_point(point, :hit_rate, name) do
    %{
      value: [point.date, point.hit_rate],
      tooltipExtra: [
        %{label: name, value: percentage(point.hit_rate)},
        %{label: dgettext("dashboard_builds", "Hits"), value: format_number(point.hits)},
        %{label: dgettext("dashboard_builds", "Misses"), value: format_number(point.misses)},
        %{label: dgettext("dashboard_builds", "Recorded lookups"), value: format_number(point.hits + point.misses)}
      ]
    }
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

  defp duration_group_options(resource) do
    primary =
      if resource.kind == "cache_action",
        do: %{value: "cache_status", label: dgettext("dashboard_builds", "Cache result")},
        else: %{value: "status", label: dgettext("dashboard_builds", "Outcome")}

    [primary, %{value: "environment", label: dgettext("dashboard_builds", "Environment")}]
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
  defp scatter_group(row, "cache_status"), do: row.cache_status
  defp scatter_group(row, _group), do: row.status

  defp scatter_group_label(true, "environment"), do: Labels.environment("ci")
  defp scatter_group_label(false, "environment"), do: Labels.environment("local")
  defp scatter_group_label(_group, "environment"), do: dgettext("dashboard_builds", "Not reported")
  defp scatter_group_label("none", _dimension), do: dgettext("dashboard_builds", "Not reported")
  defp scatter_group_label(group, _dimension), do: Labels.status(group)

  defp scatter_group_color(group) do
    color =
      Map.get(
        %{
          "failure" => "destructive",
          "success" => "p99",
          "miss" => "p50",
          "write" => "p90",
          "hit_local" => "secondary",
          "hit_remote" => "primary",
          "hit" => "tertiary",
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
      tooltipExtra: [
        %{label: dgettext("dashboard_builds", "Outcome"), value: Labels.status(row.status)},
        %{label: dgettext("dashboard_builds", "Cache"), value: scatter_group_label(row.cache_status, "cache_status")},
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

  defp reported(value) when value in [nil, ""], do: dgettext("dashboard_builds", "Not reported")
  defp reported(value), do: value

  defp scatter_point_path(assigns, row) do
    if assigns.resource.system == :bazel or row.parent_id == "" do
      params =
        assigns.params
        |> Map.drop(@activity_keys)
        |> Map.merge(reset_pagination(%{"tab" => "history", "activity-search" => row.parent_id}))

      query_path(assigns.path, params)
    else
      execution_path(assigns, row)
    end
  end

  defp chart_options(assigns) do
    formatter =
      case assigns.widget do
        "duration" -> "fn:formatMilliseconds"
        "hit_rate" -> "{value}%"
        _ -> "{value}"
      end

    dates = Enum.map(assigns.analytics.result.points, & &1.date)
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
        boundaryGap: assigns.widget == "observations",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        max: if(assigns.widget == "hit_rate", do: 100),
        interval: if(assigns.widget == "hit_rate", do: 25),
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
      },
      tooltip: %{valueFormat: formatter, dateFormat: if(assigns.preset == "last-24-hours", do: "hour", else: "date")}
    }
  end
end
