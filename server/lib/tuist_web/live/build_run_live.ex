defmodule TuistWeb.BuildRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Runs
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    run =
      case Runs.get_build(params["build_run_id"]) do
        nil ->
          raise NotFoundError, gettext("Build not found.")

        run ->
          run
      end

    slug = Projects.get_project_slug_from_id(project.id)

    run =
      run
      |> Tuist.Repo.preload([:project, :ran_by_account])
      |> Tuist.ClickHouseRepo.preload([:issues])

    command_event =
      case CommandEvents.get_command_event_by_build_run_id(run.id) do
        {:ok, event} -> event
        {:error, :not_found} -> nil
      end

    if run.project.id != project.id do
      raise NotFoundError, gettext("Build not found.")
    end

    socket =
      socket
      |> assign(:run, run)
      |> assign(:command_event, command_event)
      |> assign(:head_title, "#{gettext("Build Run")} · #{slug} · Tuist")
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
            module_breakdown_active_filters: module_breakdown_active_filters
          }
        } = socket
      ) do
    uri = URI.new!("?" <> URI.encode_query(params))
    selected_breakdown_tab = params["breakdown-tab"] || "module"

    available_filters =
      case selected_breakdown_tab do
        "file" -> file_breakdown_available_filters
        "module" -> module_breakdown_available_filters
        _ -> []
      end

    active_filters =
      case selected_breakdown_tab do
        "file" -> file_breakdown_active_filters
        "module" -> module_breakdown_active_filters
        _ -> []
      end

    socket =
      socket
      |> assign(:selected_tab, params["tab"] || "overview")
      |> assign(:uri, uri)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign_file_breakdown(params)
      |> assign_module_breakdown(params)
      |> assign(:selected_breakdown_tab, selected_breakdown_tab)

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
         not is_nil(run.project.vcs_repository_full_handle) and
         run.project.vcs_provider == :github and not is_nil(run.git_commit_sha) do
      title
      |> String.replace(
        issue.path,
        ~s(<a href="https://github.com/#{run.project.vcs_repository_full_handle}/blob/#{run.git_commit_sha}/#{issue.path}" target="_blank">#{issue.path}</a>)
      )
      |> raw()
    else
      title
    end
  end

  defp issue_message(issue, run) do
    if not is_nil(issue.path) and issue.path != "" and
         not is_nil(run.project.vcs_repository_full_handle) and
         run.project.vcs_provider == :github and not is_nil(run.git_commit_sha) do
      raw(
        gettext("%{message} in %{link}",
          message: issue.message,
          link:
            ~s(<a href="https://github.com/#{run.project.vcs_repository_full_handle}/blob/#{run.git_commit_sha}/#{issue.path}#L#{issue.starting_line}" target="_blank">#{issue.path}#L#{issue.starting_line}</a>)
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
          gettext("Failed compiling C file %{path}", path: issue.path)

        {"error", "swift_compilation"} ->
          gettext("Failed compiling Swift file %{path}", path: issue.path)

        {"error", "script_execution"} ->
          gettext("Failed executing script %{script_name}", script_name: issue.path)

        {"error", "create_static_library"} ->
          gettext("Failed creating static library %{path}", path: issue.path)

        {"error", "linker"} ->
          gettext("Failed linking %{path}", path: issue.path)

        {"error", "copy_swift_libs"} ->
          gettext("Failed copying Swift libraries %{path}", path: issue.path)

        {"error", "compile_assets_catalog"} ->
          gettext("Failed compiling assets catalog %{path}", path: issue.path)

        {"error", "compile_storyboard"} ->
          gettext("Failed compiling storyboard %{path}", path: issue.path)

        {"error", "write_auxiliary_file"} ->
          gettext("Failed writing auxiliary file %{path}", path: issue.path)

        {"error", "link_storyboards"} ->
          gettext("Failed linking storyboards %{path}", path: issue.path)

        {"error", "copy_resource_file"} ->
          gettext("Failed copying resource file %{path}", path: issue.path)

        {"error", "merge_swift_module"} ->
          gettext("Failed merging Swift module %{path}", path: issue.path)

        {"error", "xib_compilation"} ->
          gettext("Failed compiling XIB file %{path}", path: issue.path)

        {"error", "swift_aggregated_compilation"} ->
          gettext("Failed compiling Swift file %{path}", path: issue.path)

        {"error", "precompile_bridging_header"} ->
          gettext("Failed precompiling bridging header %{path}", path: issue.path)

        {"error", "validate_embedded_binary"} ->
          gettext("Failed validating embedded binary %{path}", path: issue.path)

        {"error", "validate"} ->
          gettext("Failed validating %{path}", path: issue.path)

        {"error", "other"} ->
          if is_nil(issue.path) or issue.path == "" do
            issue.title
          else
            gettext("Failed processing %{path}", path: issue.path)
          end

        {"warning", "c_compilation"} ->
          gettext("Warning when compiling C file %{path}", path: issue.path)

        {"warning", "swift_compilation"} ->
          gettext("Warning when compiling Swift file %{path}", path: issue.path)

        {"warning", "script_execution"} ->
          gettext("Warning when executing script %{script_name}", script_name: issue.path)

        {"warning", "create_static_library"} ->
          gettext("Warning when creating static library %{path}", path: issue.path)

        {"warning", "linker"} ->
          gettext("Warning when linking %{path}", path: issue.path)

        {"warning", "copy_swift_libs"} ->
          gettext("Warning when copying Swift libraries %{path}", path: issue.path)

        {"warning", "compile_assets_catalog"} ->
          gettext("Warning when compiling assets catalog %{path}", path: issue.path)

        {"warning", "compile_storyboard"} ->
          gettext("Warning when compiling storyboard %{path}", path: issue.path)

        {"warning", "write_auxiliary_file"} ->
          gettext("Warning when writing auxiliary file %{path}", path: issue.path)

        {"warning", "link_storyboards"} ->
          gettext("Warning when linking storyboards %{path}", path: issue.path)

        {"warning", "copy_resource_file"} ->
          gettext("Warning when copying resource file %{path}", path: issue.path)

        {"warning", "merge_swift_module"} ->
          gettext("Warning when merging Swift module %{path}", path: issue.path)

        {"warning", "xib_compilation"} ->
          gettext("Warning when compiling XIB file %{path}", path: issue.path)

        {"warning", "swift_aggregated_compilation"} ->
          gettext("Warning when compiling Swift file %{path}", path: issue.path)

        {"warning", "precompile_bridging_header"} ->
          gettext("Warning when precompiling bridging header %{path}", path: issue.path)

        {"warning", "validate_embedded_binary"} ->
          gettext("Warning when validating embedded binary %{path}", path: issue.path)

        {"warning", "validate"} ->
          gettext("Warning when validating %{path}", path: issue.path)

        {"warning", "other"} ->
          if is_nil(issue.path) or issue.path == "" do
            issue.title
          else
            gettext("Warning when processing %{path}", path: issue.path)
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

  defp define_file_breakdown_filters do
    [
      %Filter.Filter{
        id: "file_breakdown_compilation_duration",
        field: :compilation_duration,
        display_name: gettext("Compilation duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "file_breakdown_target",
        field: :target,
        display_name: gettext("Target"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "file_breakdown_project",
        field: :project,
        display_name: gettext("Project"),
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
        display_name: gettext("Build duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "module_breakdown_compilation_duration",
        field: :compilation_duration,
        display_name: gettext("Compilation duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "module_breakdown_name",
        field: :name,
        display_name: gettext("Name"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "module_breakdown_project",
        field: :project,
        display_name: gettext("Project"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: gettext("Status"),
        type: :option,
        options: [:success, :failure],
        options_display_names: %{
          :success => gettext("Passed"),
          :failure => gettext("Failed")
        },
        operator: :==,
        value: nil
      }
    ]
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
end
