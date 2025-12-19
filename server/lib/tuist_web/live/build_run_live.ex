defmodule TuistWeb.BuildRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Runs
  alias Tuist.Runs.CASOutput
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    run =
      case Runs.get_build(params["build_run_id"]) do
        nil ->
          raise NotFoundError, dgettext("dashboard_builds", "Build not found.")

        run ->
          run
      end

    slug = Projects.get_project_slug_from_id(project.id)

    run =
      run
      |> Tuist.Repo.preload([:project, :ran_by_account, project: :vcs_connection])
      |> Tuist.ClickHouseRepo.preload([:issues])

    command_event =
      case CommandEvents.get_command_event_by_build_run_id(run.id) do
        {:ok, event} -> event
        {:error, :not_found} -> nil
      end

    if run.project.id != project.id do
      raise NotFoundError, dgettext("dashboard_builds", "Build not found.")
    end

    cas_metrics = Runs.cas_output_metrics(run.id)
    cacheable_task_latency_metrics = Runs.cacheable_task_latency_metrics(run.id)

    test_run =
      case Runs.get_latest_test_by_build_run_id(run.id) do
        {:ok, test} -> test
        {:error, :not_found} -> nil
      end

    socket =
      socket
      |> assign(:run, run)
      |> assign(:command_event, command_event)
      |> assign(:test_run, test_run)
      |> assign(:cas_metrics, cas_metrics)
      |> assign(:cacheable_task_latency_metrics, cacheable_task_latency_metrics)
      |> assign(:head_title, "#{dgettext("dashboard_builds", "Build Run")} · #{slug} · Tuist")
      |> assign(
        :warnings_grouped_by_path,
        run.issues |> Enum.filter(&(&1.type == "warning")) |> Enum.group_by(& &1.path)
      )
      |> assign(
        :errors_grouped_by_path,
        run.issues |> Enum.filter(&(&1.type == "error")) |> Enum.group_by(& &1.path)
      )
      |> assign(:file_breakdown_available_filters, define_file_breakdown_filters())
      |> assign(:file_breakdown_active_filters, [])
      |> assign(:module_breakdown_available_filters, define_module_breakdown_filters())
      |> assign(:module_breakdown_active_filters, [])
      |> assign(:cacheable_tasks_available_filters, define_cacheable_tasks_filters())
      |> assign(:cacheable_tasks_active_filters, [])
      |> assign(:cas_outputs_available_filters, define_cas_outputs_filters())
      |> assign(:cas_outputs_active_filters, [])
      |> assign(:selected_read_latency_type, "avg")
      |> assign(:selected_write_latency_type, "avg")
      |> assign(:expanded_task_keys, MapSet.new())
      |> assign(:task_cas_outputs_map, %{})
      |> assign_async(:has_result_bundle, fn ->
        {:ok, %{has_result_bundle: (command_event && CommandEvents.has_result_bundle?(command_event)) || false}}
      end)

    {:ok, socket}
  end

  def handle_params(
        params,
        _uri,
        %{
          assigns: %{
            file_breakdown_available_filters: file_breakdown_available_filters,
            file_breakdown_active_filters: file_breakdown_active_filters,
            module_breakdown_available_filters: module_breakdown_available_filters,
            module_breakdown_active_filters: module_breakdown_active_filters,
            cacheable_tasks_available_filters: cacheable_tasks_available_filters,
            cacheable_tasks_active_filters: cacheable_tasks_active_filters,
            cas_outputs_available_filters: cas_outputs_available_filters,
            cas_outputs_active_filters: cas_outputs_active_filters
          }
        } = socket
      ) do
    uri = URI.new!("?" <> URI.encode_query(params))
    selected_breakdown_tab = params["breakdown-tab"] || "module"
    selected_cache_tab = params["cache-tab"] || "cacheable-tasks"

    selected_tab = params["tab"] || "overview"

    available_filters =
      case {selected_tab, selected_breakdown_tab, selected_cache_tab} do
        {"overview", "file", _} -> file_breakdown_available_filters
        {"overview", "module", _} -> module_breakdown_available_filters
        {"xcode-cache", _, "cacheable-tasks"} -> cacheable_tasks_available_filters
        {"xcode-cache", _, "cas-outputs"} -> cas_outputs_available_filters
        _ -> []
      end

    active_filters =
      case {selected_tab, selected_breakdown_tab, selected_cache_tab} do
        {"overview", "file", _} -> file_breakdown_active_filters
        {"overview", "module", _} -> module_breakdown_active_filters
        {"xcode-cache", _, "cacheable-tasks"} -> cacheable_tasks_active_filters
        {"xcode-cache", _, "cas-outputs"} -> cas_outputs_active_filters
        _ -> []
      end

    selected_read_latency_type = params["read-latency-type"] || "avg"
    selected_write_latency_type = params["write-latency-type"] || "avg"

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, uri)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:selected_read_latency_type, selected_read_latency_type)
      |> assign(:selected_write_latency_type, selected_write_latency_type)
      |> assign_file_breakdown(params)
      |> assign_module_breakdown(params)
      |> assign_cacheable_tasks(params)
      |> assign_cas_outputs(params)
      |> assign(:selected_breakdown_tab, selected_breakdown_tab)
      |> assign(:selected_cache_tab, selected_cache_tab)

    {
      :noreply,
      socket
    }
  end

  def handle_event(
        "search-file-breakdown",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, run: run, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds/build-runs/#{run.id}?#{uri.query |> Query.put("file-breakdown-search", search) |> Query.drop("file-breakdown-page")}"
      )

    {:noreply, socket}
  end

  def handle_event(
        "search-module-breakdown",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, run: run, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds/build-runs/#{run.id}?#{uri.query |> Query.put("module-breakdown-search", search) |> Query.drop("module-breakdown-page")}"
      )

    {:noreply, socket}
  end

  def handle_event(
        "search-cacheable-tasks",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, run: run, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds/build-runs/#{run.id}?#{uri.query |> Query.put("cacheable-tasks-search", search) |> Query.drop("cacheable-tasks-page")}"
      )

    {:noreply, socket}
  end

  def handle_event(
        "search-cas-outputs",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, run: run, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds/build-runs/#{run.id}?#{uri.query |> Query.put("cas-outputs-search", search) |> Query.drop("cas-outputs-page")}"
      )

    {:noreply, socket}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/builds/build-runs/#{socket.assigns.run.id}?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/builds/build-runs/#{socket.assigns.run.id}?#{updated_query_params}"
     )
     # There's a DOM reconciliation bug where the dropdown closes and then reappears somewhere else on the page. To remedy, just nuke it entirely.
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event(
        "select_read_latency_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, run: run, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds/build-runs/#{run.id}?#{Query.put(uri.query, "read-latency-type", type)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "select_write_latency_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, run: run, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds/build-runs/#{run.id}?#{Query.put(uri.query, "write-latency-type", type)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "toggle-expand",
        %{"row-key" => task_key},
        %{assigns: %{expanded_task_keys: expanded_task_keys}} = socket
      ) do
    updated_expanded_keys =
      if MapSet.member?(expanded_task_keys, task_key) do
        MapSet.delete(expanded_task_keys, task_key)
      else
        MapSet.put(expanded_task_keys, task_key)
      end

    {:noreply, assign(socket, :expanded_task_keys, updated_expanded_keys)}
  end

  defp file_breakdown_filters(run, params, available_filters, search) do
    base_filters =
      [
        %{field: :build_run_id, op: :==, value: run.id}
      ] ++
        Filter.Operations.convert_filters_to_flop(Filter.Operations.decode_filters_from_query(params, available_filters))

    if search && search != "" do
      base_filters ++
        [
          %{field: :path, op: :like, value: search}
        ]
    else
      base_filters
    end
  end

  defp module_breakdown_filters(run, params, available_filters, search) do
    base_filters =
      map_filter_status_value(
        [%{field: :build_run_id, op: :==, value: run.id}] ++
          Filter.Operations.convert_filters_to_flop(
            Filter.Operations.decode_filters_from_query(params, available_filters)
          )
      )

    if search && search != "" do
      base_filters ++
        [
          %{field: :name, op: :like, value: search}
        ]
    else
      base_filters
    end
  end

  defp file_breakdown_order_by(sort_by) do
    case sort_by do
      "compilation-duration" -> [:compilation_duration]
      "file" -> [:path]
      _ -> [:compilation_duration]
    end
  end

  defp assign_file_breakdown(
         %{assigns: %{run: run, file_breakdown_available_filters: available_filters}} = socket,
         params
       ) do
    file_breakdown_search = params["file-breakdown-search"] || ""
    file_breakdown_sort_by = params["file-breakdown-sort-by"] || "compilation-duration"

    default_sort_order =
      case file_breakdown_sort_by do
        "file" -> "asc"
        _ -> "desc"
      end

    file_breakdown_sort_order = params["file-breakdown-sort-order"] || default_sort_order

    file_breakdown_page =
      params["file-breakdown-page"]
      |> to_string()
      |> Integer.parse()
      |> case do
        {int, _} -> int
        :error -> 1
      end

    flop_filters = file_breakdown_filters(run, params, available_filters, file_breakdown_search)

    order_by = file_breakdown_order_by(file_breakdown_sort_by)

    order_directions = map_sort_order(file_breakdown_sort_order)

    options = %{
      filters: flop_filters,
      order_by: order_by,
      order_directions: order_directions,
      page: file_breakdown_page,
      page_size: 20
    }

    {files, files_meta} = Runs.list_build_files(options)

    filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    socket
    |> assign(:file_breakdown_search, file_breakdown_search)
    |> assign(
      :file_breakdown_files,
      files
    )
    |> assign(:file_breakdown_page, file_breakdown_page)
    |> assign(:file_breakdown_sort_by, file_breakdown_sort_by)
    |> assign(:file_breakdown_sort_order, file_breakdown_sort_order)
    |> assign(:file_breakdown_files_meta, files_meta)
    |> assign(:file_breakdown_active_filters, filters)
  end

  defp map_sort_order(sort_order) do
    case sort_order do
      "asc" -> [:asc]
      "desc" -> [:desc]
      _ -> [:desc]
    end
  end

  defp module_breakdown_order_by(module_breakdown_sort_by) do
    case module_breakdown_sort_by do
      "build-duration" -> [:build_duration]
      "compilation-duration" -> [:compilation_duration]
      "name" -> [:name]
      _ -> [:name]
    end
  end

  defp cacheable_tasks_order_by(cacheable_tasks_sort_by) do
    case cacheable_tasks_sort_by do
      "description" -> [:description]
      "key" -> [:key]
      _ -> [:description]
    end
  end

  defp assign_module_breakdown(
         %{assigns: %{run: run, module_breakdown_available_filters: available_filters}} = socket,
         params
       ) do
    module_breakdown_search = params["module-breakdown-search"] || ""
    module_breakdown_sort_by = params["module-breakdown-sort-by"] || "name"

    default_sort_order =
      case module_breakdown_sort_by do
        "name" -> "asc"
        _ -> "desc"
      end

    module_breakdown_sort_order = params["module-breakdown-sort-order"] || default_sort_order

    module_breakdown_page =
      params["module-breakdown-page"]
      |> to_string()
      |> Integer.parse()
      |> case do
        {int, _} -> int
        :error -> 1
      end

    flop_filters =
      module_breakdown_filters(run, params, available_filters, module_breakdown_search)

    order_by = module_breakdown_order_by(module_breakdown_sort_by)

    order_directions = map_sort_order(module_breakdown_sort_order)

    options = %{
      filters: flop_filters,
      order_by: order_by,
      order_directions: order_directions,
      page: module_breakdown_page,
      page_size: 20
    }

    {modules, modules_meta} = Runs.list_build_targets(options)

    filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    socket
    |> assign(:module_breakdown_search, module_breakdown_search)
    |> assign(
      :module_breakdown_modules,
      modules
    )
    |> assign(:module_breakdown_page, module_breakdown_page)
    |> assign(:module_breakdown_sort_by, module_breakdown_sort_by)
    |> assign(:module_breakdown_sort_order, module_breakdown_sort_order)
    |> assign(:module_breakdown_modules_meta, modules_meta)
    |> assign(:module_breakdown_active_filters, filters)
  end

  defp map_filter_status_value(filters) do
    map_value = fn filter ->
      case filter.value do
        :success -> %{filter | value: 0}
        :failure -> %{filter | value: 1}
        _ -> filter
      end
    end

    Enum.map(filters, fn filter ->
      if filter.field == :status do
        map_value.(filter)
      else
        filter
      end
    end)
  end

  attr(:issues, :list, required: true)
  attr(:path, :string, required: true)
  attr(:run, :map, required: true)
  attr(:type, :string, required: true, values: ~w(error warning))

  def issue_card(assigns) do
    ~H"""
    <div
      id={"#{@path |> String.replace("/", "-")}-issue-collapsible"}
      phx-hook="NooraCollapsible"
      data-part="collapsible"
      data-state="closed"
      data-type={@type}
      class="issue-card"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon">
              <%= if @type == "error" do %>
                <.alert_circle />
              <% else %>
                <.alert_hexagon />
              <% end %>
            </div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">
                {issue_title_for_type(hd(@issues), @run, @type)}
              </h3>
              <span :if={hd(@issues).target != "" || hd(@issues).project != ""} data-part="subtitle">
                {[hd(@issues).target, hd(@issues).project]
                |> Enum.filter(&(&1 != ""))
                |> Enum.join(" • ")}
              </span>
            </div>
            <.badge
              label={Enum.count(@issues)}
              color={if @type == "error", do: "destructive", else: "warning"}
              style="light-fill"
              size="small"
            />
          </div>
          <.neutral_button data-part="closed-collapsible-button" variant="secondary" size="small">
            <.chevron_down />
          </.neutral_button>
          <.neutral_button data-part="open-collapsible-button" variant="secondary" size="small">
            <.chevron_up />
          </.neutral_button>
        </div>
        <div data-part="content" data-state="closed" )>
          <%= for issue <- @issues do %>
            <span data-part="issue">
              {issue_message(issue, @run)}
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp issue_title(title, issue, run) do
    if not is_nil(issue.path) and String.contains?(title, issue.path) and
         not is_nil(run.project.vcs_connection) and
         run.project.vcs_connection.provider == :github and not is_nil(run.git_commit_sha) do
      title
      |> String.replace(
        issue.path,
        ~s(<a href="https://github.com/#{run.project.vcs_connection.repository_full_handle}/blob/#{run.git_commit_sha}/#{issue.path}" target="_blank">#{issue.path}</a>)
      )
      |> raw()
    else
      title
    end
  end

  defp issue_message(issue, run) do
    if not is_nil(issue.path) and issue.path != "" and
         not is_nil(run.project.vcs_connection) and
         run.project.vcs_connection.provider == :github and not is_nil(run.git_commit_sha) do
      raw(
        dgettext("dashboard_builds", "%{message} in %{link}",
          message: issue.message,
          link:
            ~s(<a href="https://github.com/#{run.project.vcs_connection.repository_full_handle}/blob/#{run.git_commit_sha}/#{issue.path}#L#{issue.starting_line}" target="_blank">#{issue.path}#L#{issue.starting_line}</a>)
        )
      )
    else
      issue.message
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp issue_title_for_type(issue, run, type) do
    title =
      case {type, issue.step_type} do
        {"error", "c_compilation"} ->
          dgettext("dashboard_builds", "Failed compiling C file %{path}", path: issue.path)

        {"error", "swift_compilation"} ->
          dgettext("dashboard_builds", "Failed compiling Swift file %{path}", path: issue.path)

        {"error", "script_execution"} ->
          dgettext("dashboard_builds", "Failed executing script %{script_name}", script_name: issue.path)

        {"error", "create_static_library"} ->
          dgettext("dashboard_builds", "Failed creating static library %{path}", path: issue.path)

        {"error", "linker"} ->
          dgettext("dashboard_builds", "Failed linking %{path}", path: issue.path)

        {"error", "copy_swift_libs"} ->
          dgettext("dashboard_builds", "Failed copying Swift libraries %{path}", path: issue.path)

        {"error", "compile_assets_catalog"} ->
          dgettext("dashboard_builds", "Failed compiling assets catalog %{path}", path: issue.path)

        {"error", "compile_storyboard"} ->
          dgettext("dashboard_builds", "Failed compiling storyboard %{path}", path: issue.path)

        {"error", "write_auxiliary_file"} ->
          dgettext("dashboard_builds", "Failed writing auxiliary file %{path}", path: issue.path)

        {"error", "link_storyboards"} ->
          dgettext("dashboard_builds", "Failed linking storyboards %{path}", path: issue.path)

        {"error", "copy_resource_file"} ->
          dgettext("dashboard_builds", "Failed copying resource file %{path}", path: issue.path)

        {"error", "merge_swift_module"} ->
          dgettext("dashboard_builds", "Failed merging Swift module %{path}", path: issue.path)

        {"error", "xib_compilation"} ->
          dgettext("dashboard_builds", "Failed compiling XIB file %{path}", path: issue.path)

        {"error", "swift_aggregated_compilation"} ->
          dgettext("dashboard_builds", "Failed compiling Swift file %{path}", path: issue.path)

        {"error", "precompile_bridging_header"} ->
          dgettext("dashboard_builds", "Failed precompiling bridging header %{path}", path: issue.path)

        {"error", "validate_embedded_binary"} ->
          dgettext("dashboard_builds", "Failed validating embedded binary %{path}", path: issue.path)

        {"error", "validate"} ->
          dgettext("dashboard_builds", "Failed validating %{path}", path: issue.path)

        {"error", "other"} ->
          if is_nil(issue.path) or issue.path == "" do
            issue.title
          else
            dgettext("dashboard_builds", "Failed processing %{path}", path: issue.path)
          end

        {"warning", "c_compilation"} ->
          dgettext("dashboard_builds", "Warning when compiling C file %{path}", path: issue.path)

        {"warning", "swift_compilation"} ->
          dgettext("dashboard_builds", "Warning when compiling Swift file %{path}", path: issue.path)

        {"warning", "script_execution"} ->
          dgettext("dashboard_builds", "Warning when executing script %{script_name}", script_name: issue.path)

        {"warning", "create_static_library"} ->
          dgettext("dashboard_builds", "Warning when creating static library %{path}", path: issue.path)

        {"warning", "linker"} ->
          dgettext("dashboard_builds", "Warning when linking %{path}", path: issue.path)

        {"warning", "copy_swift_libs"} ->
          dgettext("dashboard_builds", "Warning when copying Swift libraries %{path}", path: issue.path)

        {"warning", "compile_assets_catalog"} ->
          dgettext("dashboard_builds", "Warning when compiling assets catalog %{path}", path: issue.path)

        {"warning", "compile_storyboard"} ->
          dgettext("dashboard_builds", "Warning when compiling storyboard %{path}", path: issue.path)

        {"warning", "write_auxiliary_file"} ->
          dgettext("dashboard_builds", "Warning when writing auxiliary file %{path}", path: issue.path)

        {"warning", "link_storyboards"} ->
          dgettext("dashboard_builds", "Warning when linking storyboards %{path}", path: issue.path)

        {"warning", "copy_resource_file"} ->
          dgettext("dashboard_builds", "Warning when copying resource file %{path}", path: issue.path)

        {"warning", "merge_swift_module"} ->
          dgettext("dashboard_builds", "Warning when merging Swift module %{path}", path: issue.path)

        {"warning", "xib_compilation"} ->
          dgettext("dashboard_builds", "Warning when compiling XIB file %{path}", path: issue.path)

        {"warning", "swift_aggregated_compilation"} ->
          dgettext("dashboard_builds", "Warning when compiling Swift file %{path}", path: issue.path)

        {"warning", "precompile_bridging_header"} ->
          dgettext("dashboard_builds", "Warning when precompiling bridging header %{path}", path: issue.path)

        {"warning", "validate_embedded_binary"} ->
          dgettext("dashboard_builds", "Warning when validating embedded binary %{path}", path: issue.path)

        {"warning", "validate"} ->
          dgettext("dashboard_builds", "Warning when validating %{path}", path: issue.path)

        {"warning", "other"} ->
          if is_nil(issue.path) or issue.path == "" do
            issue.title
          else
            dgettext("dashboard_builds", "Warning when processing %{path}", path: issue.path)
          end
      end

    issue_title(title, issue, run)
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  def file_breakdown_column_patch_sort(
        %{uri: uri, file_breakdown_sort_by: file_breakdown_sort_by, file_breakdown_sort_order: file_breakdown_sort_order} =
          _assigns,
        column_value
      ) do
    sort_order =
      case {file_breakdown_sort_by == column_value, file_breakdown_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    "?#{uri.query |> Query.put("file-breakdown-sort-by", column_value) |> Query.put("file-breakdown-sort-order", sort_order) |> Query.drop("file-breakdown-page")}"
  end

  def file_breakdown_dropdown_item_patch_sort(file_breakdown_sort_by, uri) do
    query =
      uri.query
      |> Query.put("file-breakdown-sort-by", file_breakdown_sort_by)
      |> Query.drop("file-breakdown-page")
      |> Query.drop("file-breakdown-sort-order")

    "?#{query}"
  end

  def module_breakdown_column_patch_sort(
        %{
          uri: uri,
          module_breakdown_sort_by: module_breakdown_sort_by,
          module_breakdown_sort_order: module_breakdown_sort_order
        } = _assigns,
        column_value
      ) do
    sort_order =
      case {module_breakdown_sort_by == column_value, module_breakdown_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    "?#{uri.query |> Query.put("module-breakdown-sort-by", column_value) |> Query.put("module-breakdown-sort-order", sort_order) |> Query.drop("module-breakdown-page")}"
  end

  def module_breakdown_dropdown_item_patch_sort(module_breakdown_sort_by, uri) do
    query =
      uri.query
      |> Query.put("module-breakdown-sort-by", module_breakdown_sort_by)
      |> Query.drop("module-breakdown-page")
      |> Query.drop("module-breakdown-sort-order")

    "?#{query}"
  end

  def cacheable_tasks_column_patch_sort(
        %{
          uri: uri,
          cacheable_tasks_sort_by: cacheable_tasks_sort_by,
          cacheable_tasks_sort_order: cacheable_tasks_sort_order
        } = _assigns,
        column_value
      ) do
    sort_order =
      case {cacheable_tasks_sort_by == column_value, cacheable_tasks_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    "?#{uri.query |> Query.put("cacheable-tasks-sort-by", column_value) |> Query.put("cacheable-tasks-sort-order", sort_order) |> Query.drop("cacheable-tasks-page")}"
  end

  defp define_file_breakdown_filters do
    [
      %Filter.Filter{
        id: "file_breakdown_compilation_duration",
        field: :compilation_duration,
        display_name: dgettext("dashboard_builds", "Compilation duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "file_breakdown_target",
        field: :target,
        display_name: dgettext("dashboard_builds", "Target"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "file_breakdown_project",
        field: :project,
        display_name: dgettext("dashboard_builds", "Project"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  defp define_module_breakdown_filters do
    [
      %Filter.Filter{
        id: "module_breakdown_build_duration",
        field: :build_duration,
        display_name: dgettext("dashboard_builds", "Build duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "module_breakdown_compilation_duration",
        field: :compilation_duration,
        display_name: dgettext("dashboard_builds", "Compilation duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "module_breakdown_name",
        field: :name,
        display_name: dgettext("dashboard_builds", "Name"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "module_breakdown_project",
        field: :project,
        display_name: dgettext("dashboard_builds", "Project"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_builds", "Status"),
        type: :option,
        options: [:success, :failure],
        options_display_names: %{
          :success => dgettext("dashboard_builds", "Passed"),
          :failure => dgettext("dashboard_builds", "Failed")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  defp assign_cacheable_tasks(
         %{assigns: %{run: run, cacheable_tasks_available_filters: available_filters}} = socket,
         params
       ) do
    cacheable_tasks_search = params["cacheable-tasks-search"] || ""
    cacheable_tasks_sort_by = params["cacheable-tasks-sort-by"] || "description"

    default_sort_order =
      case cacheable_tasks_sort_by do
        "description" -> "desc"
        "key" -> "desc"
        _ -> "desc"
      end

    cacheable_tasks_sort_order = params["cacheable-tasks-sort-order"] || default_sort_order

    cacheable_tasks_page =
      params["cacheable-tasks-page"]
      |> to_string()
      |> Integer.parse()
      |> case do
        {int, _} -> int
        :error -> 1
      end

    flop_filters = cacheable_tasks_filters(run, params, available_filters, cacheable_tasks_search)

    order_by = cacheable_tasks_order_by(cacheable_tasks_sort_by)

    order_directions = map_sort_order(cacheable_tasks_sort_order)

    options = %{
      filters: flop_filters,
      page: cacheable_tasks_page,
      page_size: 50,
      order_by: order_by,
      order_directions: order_directions
    }

    {tasks, tasks_meta} = Runs.list_cacheable_tasks(options)

    # Fetch CAS outputs for all tasks on the current page
    all_node_ids =
      tasks
      |> Enum.flat_map(& &1.cas_output_node_ids)
      |> Enum.uniq()

    cas_outputs = Runs.get_cas_outputs_by_node_ids(run.id, all_node_ids, distinct: true)

    # Create a map from task key to its CAS outputs
    task_cas_outputs_map =
      Map.new(tasks, fn task ->
        outputs =
          Enum.filter(cas_outputs, fn output ->
            output.node_id in task.cas_output_node_ids
          end)

        {task.key, outputs}
      end)

    filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    socket
    |> assign(:cacheable_tasks_search, cacheable_tasks_search)
    |> assign(:cacheable_tasks, tasks)
    |> assign(:cacheable_tasks_page, cacheable_tasks_page)
    |> assign(:cacheable_tasks_meta, tasks_meta)
    |> assign(:cacheable_tasks_active_filters, filters)
    |> assign(:cacheable_tasks_sort_by, cacheable_tasks_sort_by)
    |> assign(:cacheable_tasks_sort_order, cacheable_tasks_sort_order)
    |> assign(:task_cas_outputs_map, task_cas_outputs_map)
  end

  def empty_tab_state_background(assigns) do
    ~H"""
    <svg
      width="1168"
      height="286"
      viewBox="0 0 1168 286"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <mask
        id="mask0_3205_55446"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="1168"
        height="286"
      >
        <rect width="1168" height="286" fill="url(#paint0_radial_3205_55446)" />
      </mask>
      <g mask="url(#mask0_3205_55446)">
        <g opacity="0.08">
          <circle cx="24" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="80" cy="87" r="4" fill="#171A1C" />
          <circle cx="136" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="192" cy="87" r="4" fill="#848F9A" />
          <circle cx="248" cy="87" r="4" fill="#171A1C" />
          <circle cx="304" cy="87" r="4" fill="#848F9A" />
          <circle cx="360" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="416" cy="87" r="4" fill="#848F9A" />
          <circle cx="472" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="528" cy="87" r="4" fill="#848F9A" />
          <circle cx="584" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="640" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="696" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="752" cy="87" r="4" fill="#9DA6AF" />
          <circle cx="808" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="864" cy="87" r="4" fill="#848F9A" />
          <circle cx="920" cy="87" r="4" fill="#848F9A" />
          <circle cx="976" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="1032" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="1088" cy="87" r="4" fill="#9DA6AF" />
          <circle cx="1144" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="24" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="80" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="136" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="192" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="248" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="304" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="360" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="416" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="472" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="528" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="584" cy="143" r="4" fill="#848F9A" />
          <circle cx="640" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="696" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="752" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="808" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="864" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="920" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="976" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="1032" cy="143" r="4" fill="#848F9A" />
          <circle cx="1088" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="1144" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="276" cy="199" r="4" fill="#9DA6AF" />
          <circle cx="332" cy="199" r="4" fill="#9DA6AF" />
          <circle cx="388" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="444" cy="199" r="4" fill="#848F9A" />
          <circle cx="500" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="556" cy="199" r="4" fill="#848F9A" />
          <circle cx="612" cy="199" r="4" fill="#9DA6AF" />
          <circle cx="668" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="724" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="780" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="836" cy="199" r="4" fill="#848F9A" />
          <circle cx="892" cy="199" r="4" fill="#171A1C" />
        </g>
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_3205_55446"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(584 143) rotate(90) scale(396.632 1101.03)"
        >
          <stop />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end

  defp cacheable_tasks_filters(run, params, available_filters, search) do
    base_filters =
      [%{field: :build_run_id, op: :==, value: run.id}] ++
        (params
         |> Filter.Operations.decode_filters_from_query(available_filters)
         |> Filter.Operations.convert_filters_to_flop()
         |> Enum.map(&remap_cacheable_task_type_field/1))

    if search && search != "" do
      base_filters ++
        [
          %{field: :key, op: :like, value: search}
        ]
    else
      base_filters
    end
  end

  defp define_cacheable_tasks_filters do
    cacheable_task_type_options = ["clang", "swift"]

    [
      %Filter.Filter{
        id: "cacheable_task_type",
        field: :type,
        display_name: dgettext("dashboard_builds", "Type"),
        type: :option,
        options: cacheable_task_type_options,
        options_display_names: %{
          "clang" => "Clang",
          "swift" => "Swift"
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_builds", "Hit"),
        type: :option,
        options: ["hit_local", "hit_remote", "miss"],
        options_display_names: %{
          "hit_local" => dgettext("dashboard_builds", "Local"),
          "hit_remote" => dgettext("dashboard_builds", "Remote"),
          "miss" => dgettext("dashboard_builds", "Missed")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  defp define_cas_outputs_filters do
    cas_output_type_options = CASOutput.valid_types() |> List.delete("unknown") |> Enum.sort()

    [
      %Filter.Filter{
        id: "operation",
        field: :operation,
        display_name: dgettext("dashboard_builds", "Status"),
        type: :option,
        options: ["download", "upload"],
        options_display_names: %{
          "download" => dgettext("dashboard_builds", "Download"),
          "upload" => dgettext("dashboard_builds", "Upload")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "cas_output_type",
        field: :type,
        display_name: dgettext("dashboard_builds", "Type"),
        type: :option,
        options: cas_output_type_options,
        options_display_names: Map.new(cas_output_type_options, &{&1, &1}),
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "cas_output_size",
        field: :size,
        display_name: dgettext("dashboard_builds", "Size (MB)"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "cas_output_compressed_size",
        field: :compressed_size,
        display_name: dgettext("dashboard_builds", "Compressed Size (MB)"),
        type: :number,
        operator: :>,
        value: ""
      }
    ]
  end

  defp cas_outputs_filters(run, params, available_filters, search) do
    base_filters =
      [%{field: :build_run_id, op: :==, value: run.id}] ++
        (params
         |> Filter.Operations.decode_filters_from_query(available_filters)
         |> Filter.Operations.convert_filters_to_flop()
         |> Enum.map(&convert_mb_to_bytes/1)
         |> Enum.map(&remap_cas_output_type_field/1))

    if search && search != "" do
      base_filters ++
        [
          %{field: :node_id, op: :like, value: search}
        ]
    else
      base_filters
    end
  end

  defp convert_mb_to_bytes(%{field: field, value: value} = filter) when field in [:size, :compressed_size] do
    case parse_number(value) do
      nil -> filter
      number -> %{filter | value: trunc(number * 1024 * 1024)}
    end
  end

  defp convert_mb_to_bytes(filter), do: filter

  defp remap_cas_output_type_field(%{field: :cas_output_type} = filter) do
    %{filter | field: :type}
  end

  defp remap_cas_output_type_field(filter), do: filter

  defp remap_cacheable_task_type_field(%{field: :cacheable_task_type} = filter) do
    %{filter | field: :type}
  end

  defp remap_cacheable_task_type_field(filter), do: filter

  defp parse_number(value) when is_number(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  defp parse_number(_), do: nil

  defp cas_outputs_order_by(sort_by) do
    case sort_by do
      "node-id" -> [:node_id]
      "size" -> [:size]
      "compressed-size" -> [:compressed_size]
      _ -> [:compressed_size]
    end
  end

  defp assign_cas_outputs(%{assigns: %{run: run, cas_outputs_available_filters: available_filters}} = socket, params) do
    cas_outputs_search = params["cas-outputs-search"] || ""
    cas_outputs_sort_by = params["cas-outputs-sort-by"] || "compressed-size"

    default_sort_order =
      case cas_outputs_sort_by do
        "node-id" -> "asc"
        _ -> "desc"
      end

    cas_outputs_sort_order = params["cas-outputs-sort-order"] || default_sort_order

    cas_outputs_page =
      params["cas-outputs-page"]
      |> to_string()
      |> Integer.parse()
      |> case do
        {int, _} -> int
        :error -> 1
      end

    flop_filters = cas_outputs_filters(run, params, available_filters, cas_outputs_search)

    order_by = cas_outputs_order_by(cas_outputs_sort_by)

    order_directions = map_sort_order(cas_outputs_sort_order)

    options = %{
      filters: flop_filters,
      page: cas_outputs_page,
      page_size: 50,
      order_by: order_by,
      order_directions: order_directions
    }

    {outputs, outputs_meta} = Runs.list_cas_outputs(options)

    filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    socket
    |> assign(:cas_outputs_search, cas_outputs_search)
    |> assign(:cas_outputs, outputs)
    |> assign(:cas_outputs_page, cas_outputs_page)
    |> assign(:cas_outputs_meta, outputs_meta)
    |> assign(:cas_outputs_active_filters, filters)
    |> assign(:cas_outputs_sort_by, cas_outputs_sort_by)
    |> assign(:cas_outputs_sort_order, cas_outputs_sort_order)
  end

  def cas_outputs_column_patch_sort(
        %{uri: uri, cas_outputs_sort_by: cas_outputs_sort_by, cas_outputs_sort_order: cas_outputs_sort_order} = _assigns,
        column_value
      ) do
    sort_order =
      case {cas_outputs_sort_by == column_value, cas_outputs_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    "?#{uri.query |> Query.put("cas-outputs-sort-by", column_value) |> Query.put("cas-outputs-sort-order", sort_order) |> Query.drop("cas-outputs-page")}"
  end

  def cas_outputs_dropdown_item_patch_sort(cas_outputs_sort_by, uri) do
    query =
      uri.query
      |> Query.put("cas-outputs-sort-by", cas_outputs_sort_by)
      |> Query.drop("cas-outputs-page")
      |> Query.drop("cas-outputs-sort-order")

    "?#{query}"
  end

  def cache_chart_border_radius(local_hits, remote_hits, misses, category) do
    has_local = local_hits > 0
    has_remote = remote_hits > 0
    has_misses = misses > 0

    case category do
      :local when has_local ->
        if not has_remote and not has_misses do
          [6, 6, 6, 6]
        else
          [6, 0, 0, 6]
        end

      :remote when has_remote ->
        cond do
          not has_local and not has_misses -> [6, 6, 6, 6]
          not has_local and not has_misses -> [6, 6, 6, 6]
          not has_local and has_misses -> [6, 0, 0, 6]
          has_local and not has_misses -> [0, 6, 6, 0]
          true -> [0, 0, 0, 0]
        end

      :misses when has_misses ->
        if not has_local and not has_remote do
          [6, 6, 6, 6]
        else
          [0, 6, 6, 0]
        end

      _ ->
        [0, 0, 0, 0]
    end
  end
end
