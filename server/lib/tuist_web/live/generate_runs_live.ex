defmodule TuistWeb.GenerateRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.CacheEndpointFormatter
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_builds", "Generate Runs")} · #{slug} · Tuist")
      |> assign(:available_filters, define_filters(project))

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: _project}} = socket) do
    uri = URI.new!("?" <> URI.encode_query(params))

    generate_runs_sort_by = params["generate_runs_sort_by"] || "ran_at"
    generate_runs_sort_order = params["generate_runs_sort_order"] || "desc"

    params =
      if not Map.has_key?(socket.assigns, :current_params) and Query.has_cursor?(params) do
        Query.clear_cursors(params)
      else
        params
      end

    {
      :noreply,
      socket
      |> assign(
        :uri,
        uri
      )
      |> assign(
        :generate_runs_sort_by,
        generate_runs_sort_by
      )
      |> assign(
        :generate_runs_sort_order,
        generate_runs_sort_order
      )
      |> assign(:current_params, params)
      |> assign_generate_runs(params)
    }
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
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/module-cache/generate-runs?#{updated_params}"
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
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/module-cache/generate-runs?#{updated_query_params}"
     )
     # There's a DOM reconciliation bug where the dropdown closes and then reappears somewhere else on the page. To remedy, just nuke it entirely.
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_info({:command_event_created, %{name: "generate"}}, socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply, assign_generate_runs(socket, socket.assigns.current_params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  def assign_generate_runs(
        %{
          assigns: %{
            selected_project: project,
            generate_runs_sort_by: generate_runs_sort_by,
            generate_runs_sort_order: generate_runs_sort_order,
            available_filters: available_filters
          }
        } = socket,
        params
      ) do
    filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    order_by = String.to_atom(generate_runs_sort_by)
    order_direction = String.to_atom(generate_runs_sort_order)

    {generate_runs, generate_runs_meta} =
      list_generate_runs(project.id, params, order_by, order_direction, filters)

    socket
    |> assign(:active_filters, filters)
    |> assign(:generate_runs, generate_runs)
    |> assign(:generate_runs_meta, generate_runs_meta)
  end

  defp list_generate_runs(project_id, %{"after" => after_cursor}, order_by, order_direction, filters) do
    list_generate_runs(project_id,
      after: after_cursor,
      order_by: order_by,
      order_direction: order_direction,
      filters: filters
    )
  end

  defp list_generate_runs(project_id, %{"before" => before}, order_by, order_direction, filters) do
    list_generate_runs(project_id,
      before: before,
      order_by: order_by,
      order_direction: order_direction,
      filters: filters
    )
  end

  defp list_generate_runs(project_id, _params, order_by, order_direction, filters) do
    list_generate_runs(project_id,
      order_by: order_by,
      order_direction: order_direction,
      filters: filters
    )
  end

  defp list_generate_runs(project_id, attrs) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project_id},
        %{field: :name, op: :in, value: ["generate"]}
        | build_flop_filters(Keyword.get(attrs, :filters, []))
      ],
      order_by: [Keyword.get(attrs, :order_by, :ran_at)],
      order_directions: [Keyword.get(attrs, :order_direction, :desc)]
    }

    options =
      cond do
        not is_nil(Keyword.get(attrs, :before)) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, Keyword.get(attrs, :before))

        not is_nil(Keyword.get(attrs, :after)) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, Keyword.get(attrs, :after))

        true ->
          Map.put(options, :first, 20)
      end

    CommandEvents.list_command_events(options)
  end

  defp build_flop_filters(filters) do
    {ran_by, filters} = Enum.split_with(filters, &(&1.id == "ran_by"))
    flop_filters = Filter.Operations.convert_filters_to_flop(filters)

    ran_by_flop_filters =
      Enum.flat_map(ran_by, fn
        %{value: :ci, operator: op} ->
          [%{field: :is_ci, op: op, value: true}]

        %{value: value, operator: op} when not is_nil(value) ->
          [%{field: :user_id, op: op, value: value}]

        _ ->
          []
      end)

    flop_filters ++ ran_by_flop_filters
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  def column_patch_sort(
        %{uri: uri, generate_runs_sort_by: generate_runs_sort_by, generate_runs_sort_order: generate_runs_sort_order} =
          _assigns,
        column_value
      ) do
    sort_order =
      case {generate_runs_sort_by == column_value, generate_runs_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("generate_runs_sort_by", column_value)
      |> Map.put("generate_runs_sort_order", sort_order)
      |> Query.clear_cursors()

    "?#{URI.encode_query(query_params)}"
  end

  def generate_runs_dropdown_item_patch_sort(generate_runs_sort_by, uri) do
    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("generate_runs_sort_by", generate_runs_sort_by)
      |> Query.clear_cursors()
      |> Map.delete("generate_runs_sort_order")

    "?#{URI.encode_query(query_params)}"
  end

  defp define_filters(project) do
    base = [
      %Filter.Filter{
        id: "name",
        field: :name,
        display_name: dgettext("dashboard_builds", "Command"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_builds", "Status"),
        type: :option,
        options: [0, 1],
        options_display_names: %{
          0 => dgettext("dashboard_builds", "Passed"),
          1 => dgettext("dashboard_builds", "Failed")
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
        id: "hit_rate",
        field: :hit_rate,
        display_name: dgettext("dashboard_builds", "Hit rate"),
        type: :percentage,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "cache_endpoint",
        field: :cache_endpoint,
        display_name: dgettext("dashboard_builds", "Cache Endpoint"),
        type: :option,
        options: cache_endpoint_options(),
        options_display_names: cache_endpoint_display_names("tuist.dev"),
        operator: :==,
        value: nil
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
