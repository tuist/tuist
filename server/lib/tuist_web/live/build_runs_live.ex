defmodule TuistWeb.BuildRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Accounts
  alias Tuist.Projects
  alias Tuist.Runs
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = Projects.get_project_slug_from_id(project.id)
    configurations = Runs.project_build_configurations(project)

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_builds", "Build Runs")} · #{slug} · Tuist")
      |> assign(:available_filters, define_filters(project, configurations))

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    uri = URI.new!("?" <> URI.encode_query(params))

    build_runs_sort_by = params["build-runs-sort-by"] || "ran-at"
    build_runs_sort_order = params["build-runs-sort-order"] || "desc"

    params =
      if not Map.has_key?(socket.assigns, :current_params) and Query.has_cursor?(params) do
        Query.clear_cursors(params)
      else
        params
      end

    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:current_params, params)
      |> assign(:build_runs_sort_by, build_runs_sort_by)
      |> assign(:build_runs_sort_order, build_runs_sort_order)
      |> assign_build_runs(params)

    {
      :noreply,
      socket
    }
  end

  def handle_info({:build_created, _build}, socket) do
    # Only update when pagination is inactive
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply, assign_build_runs(socket, socket.assigns.current_params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_build_runs(
         %{
           assigns: %{
             selected_project: project,
             build_runs_sort_by: build_runs_sort_by,
             build_runs_sort_order: build_runs_sort_order,
             available_filters: available_filters
           }
         } = socket,
         params
       ) do
    filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    base_flop_filters = [
      %{field: :project_id, op: :==, value: project.id}
    ]

    filter_flop_filters = build_flop_filters(filters)
    flop_filters = base_flop_filters ++ filter_flop_filters

    order_by =
      case build_runs_sort_by do
        "duration" -> [:duration]
        _ -> [:inserted_at]
      end

    order_directions =
      case build_runs_sort_order do
        "asc" -> [:asc]
        _ -> [:desc]
      end

    options =
      build_runs_options_with_paging(
        %{filters: flop_filters, order_by: order_by, order_directions: order_directions},
        params
      )

    {build_runs, build_runs_meta} = Runs.list_build_runs(options, preload: :ran_by_account)

    socket
    |> assign(:active_filters, filters)
    |> assign(:build_runs, build_runs)
    |> assign(:build_runs_meta, build_runs_meta)
  end

  defp build_runs_options_with_paging(options, params) do
    cond do
      not is_nil(Map.get(params, "before")) ->
        options
        |> Map.put(:last, 20)
        |> Map.put(:before, Map.get(params, "before"))

      not is_nil(Map.get(params, "after")) ->
        options
        |> Map.put(:first, 20)
        |> Map.put(:after, Map.get(params, "after"))

      true ->
        Map.put(options, :first, 20)
    end
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  def column_patch_sort(
        %{uri: uri, build_runs_sort_by: build_runs_sort_by, build_runs_sort_order: build_runs_sort_order} = _assigns,
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
      |> Query.clear_cursors()

    "?#{URI.encode_query(query_params)}"
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Query.clear_cursors()

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/builds/build-runs?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Query.clear_cursors()

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/builds/build-runs?#{updated_query_params}"
     )
     # There's a DOM reconciliation bug where the dropdown closes and then reappears somewhere else on the page. To remedy, just nuke it entirely.
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  defp build_flop_filters(filters) do
    {ran_by, filters} = Enum.split_with(filters, &(&1.id == "ran_by"))
    flop_filters = Filter.Operations.convert_filters_to_flop(filters)

    ran_by_flop_filters =
      Enum.flat_map(ran_by, fn
        %{value: :ci, operator: op} ->
          [%{field: :is_ci, op: op, value: true}]

        %{value: value, operator: op} when not is_nil(value) ->
          [%{field: :account_id, op: op, value: value}]

        _ ->
          []
      end)

    flop_filters ++ ran_by_flop_filters
  end

  defp define_filters(project, configurations) do
    base = [
      %Filter.Filter{
        id: "scheme",
        field: :scheme,
        display_name: dgettext("dashboard_builds", "Scheme"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "configuration",
        field: :configuration,
        display_name: dgettext("dashboard_builds", "Configuration"),
        type: :option,
        options: configurations,
        options_display_names: Map.new(configurations, &{&1, &1}),
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_builds", "Status"),
        type: :option,
        options: [:success, :failure],
        options_display_names: %{
          success: dgettext("dashboard_builds", "Passed"),
          failure: dgettext("dashboard_builds", "Failed")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: dgettext("dashboard_builds", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "category",
        field: :category,
        display_name: dgettext("dashboard_builds", "Category"),
        type: :option,
        options: [:incremental, :clean],
        options_display_names: %{
          build: dgettext("dashboard_builds", "Build"),
          test: dgettext("dashboard_builds", "Test"),
          archive: dgettext("dashboard_builds", "Archive")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "xcode_version",
        field: :xcode_version,
        display_name: dgettext("dashboard_builds", "Xcode version"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "macos_version",
        field: :macos_version,
        display_name: dgettext("dashboard_builds", "macOS version"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]

    organization =
      if Accounts.organization?(project.account) do
        {:ok, organization} = Accounts.get_organization_by_id(project.account.organization_id)
        users = Accounts.get_organization_members(organization)

        [
          %Filter.Filter{
            id: "ran_by",
            field: :ran_by,
            display_name: dgettext("dashboard_builds", "Ran by"),
            type: :option,
            options: [:ci] ++ Enum.map(users, fn user -> user.account.id end),
            options_display_names:
              Map.merge(
                %{ci: "CI"},
                Map.new(users, fn user -> {user.account.id, user.account.name} end)
              ),
            operator: :==,
            value: nil
          }
        ]
      else
        []
      end

    base ++ organization
  end
end
