defmodule TuistWeb.GradleBuildRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Gradle
  alias Tuist.Repo
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  @page_size 20

  def assign_mount(socket) do
    assign(socket, :available_filters, define_filters())
  end

  def assign_handle_params(socket, params) do
    build_runs_sort_by = params["build-runs-sort-by"] || "ran-at"
    build_runs_sort_order = params["build-runs-sort-order"] || "desc"
    search = params["search"] || ""
    uri = URI.new!("?" <> URI.encode_query(params))

    socket
    |> assign(:uri, uri)
    |> assign(:current_params, params)
    |> assign(:build_runs_sort_by, build_runs_sort_by)
    |> assign(:build_runs_sort_order, build_runs_sort_order)
    |> assign(:build_runs_search, search)
    |> assign_build_runs(params)
  end

  def handle_event_add_filter(filter_id, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("page", "1")

    account_name = socket.assigns.selected_project.account.name
    project_name = socket.assigns.selected_project.name

    socket
    |> push_patch(to: ~p"/#{account_name}/#{project_name}/builds/build-runs?#{updated_params}")
    |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
    |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})
  end

  def handle_event_search(search, socket) do
    account_name = socket.assigns.selected_project.account.name
    project_name = socket.assigns.selected_project.name

    query =
      (socket.assigns.uri.query || "")
      |> URI.decode_query()
      |> Map.put("search", search)
      |> Map.put("page", "1")

    push_patch(
      socket,
      to: ~p"/#{account_name}/#{project_name}/builds/build-runs?#{query}",
      replace: true
    )
  end

  def handle_event_update_filter(params, socket) do
    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.put("page", "1")

    account_name = socket.assigns.selected_project.account.name
    project_name = socket.assigns.selected_project.name

    socket
    |> push_patch(to: ~p"/#{account_name}/#{project_name}/builds/build-runs?#{updated_query_params}")
    |> push_event("close-dropdown", %{id: "all", all: true})
    |> push_event("close-popover", %{id: "all", all: true})
  end

  defp assign_build_runs(
         %{
           assigns: %{
             selected_project: project,
             build_runs_sort_by: build_runs_sort_by,
             build_runs_sort_order: build_runs_sort_order,
             build_runs_search: search,
             available_filters: available_filters
           }
         } = socket,
         params
       ) do
    filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    base_flop_filters = [
      %{field: :project_id, op: :==, value: project.id}
    ]

    base_flop_filters =
      if search == "" do
        base_flop_filters
      else
        base_flop_filters ++ [%{field: :root_project_name, op: :=~, value: search}]
      end

    {is_ci_filters, remaining_filters} = Enum.split_with(filters, &(&1.id == "is_ci"))
    filter_flop_filters = Filter.Operations.convert_filters_to_flop(remaining_filters)

    is_ci_flop_filters =
      Enum.flat_map(is_ci_filters, fn
        %{value: :ci, operator: op} ->
          [%{field: :is_ci, op: op, value: true}]

        %{value: :local, operator: op} ->
          [%{field: :is_ci, op: op, value: false}]

        _ ->
          []
      end)

    flop_filters = base_flop_filters ++ filter_flop_filters ++ is_ci_flop_filters

    order_by =
      case build_runs_sort_by do
        "duration" -> [:duration_ms]
        _ -> [:inserted_at]
      end

    order_directions =
      case build_runs_sort_order do
        "asc" -> [:asc]
        _ -> [:desc]
      end

    page = String.to_integer(params["page"] || "1")

    flop_params = %{
      filters: flop_filters,
      page: page,
      page_size: @page_size,
      order_by: order_by,
      order_directions: order_directions
    }

    {builds, meta} = Gradle.list_builds(project.id, flop_params)
    builds = Repo.preload(builds, :built_by_account)

    socket
    |> assign(:active_filters, filters)
    |> assign(:build_runs, builds)
    |> assign(:build_runs_page, meta.current_page)
    |> assign(:build_runs_page_count, meta.total_pages)
  end

  def sort_icon("desc"), do: "square_rounded_arrow_down"
  def sort_icon("asc"), do: "square_rounded_arrow_up"

  def column_patch_sort(
        %{uri: uri, build_runs_sort_by: build_runs_sort_by, build_runs_sort_order: build_runs_sort_order},
        column_value
      ) do
    sort_order =
      case {build_runs_sort_by == column_value, build_runs_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "desc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("build-runs-sort-by", column_value)
      |> Map.put("build-runs-sort-order", sort_order)
      |> Map.put("page", "1")

    "?#{URI.encode_query(query_params)}"
  end

  defp define_filters do
    [
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_gradle", "Status"),
        type: :option,
        options: ["success", "failure", "cancelled"],
        options_display_names: %{
          "success" => dgettext("dashboard_gradle", "Passed"),
          "failure" => dgettext("dashboard_gradle", "Failed"),
          "cancelled" => dgettext("dashboard_gradle", "Cancelled")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: dgettext("dashboard_gradle", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "is_ci",
        field: :is_ci,
        display_name: dgettext("dashboard_gradle", "Environment"),
        type: :option,
        options: [:ci, :local],
        options_display_names: %{
          ci: dgettext("dashboard_gradle", "CI"),
          local: dgettext("dashboard_gradle", "Local")
        },
        operator: :==,
        value: nil
      }
    ]
  end
end
