defmodule TuistWeb.QuarantinedTestsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection

  alias Noora.Filter
  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @allowed_sort_fields ~w(name last_ran_at)
  @default_sort_field "last_ran_at"

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Quarantined Tests")} · #{slug} · Tuist")
      |> assign(:available_filters, define_filters(project))

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  defp define_filters(project) do
    # Get users who have manually quarantined tests
    quarantine_actors = Runs.get_quarantine_actors(project.id)

    base_filters = [
      %Filter.Filter{
        id: "module_name",
        field: "module_name",
        display_name: dgettext("dashboard_tests", "Module"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "suite_name",
        field: "suite_name",
        display_name: dgettext("dashboard_tests", "Suite"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]

    # Build quarantined_by filter with Tuist + actual users
    quarantined_by_filter = %Filter.Filter{
      id: "quarantined_by",
      field: "quarantined_by",
      display_name: dgettext("dashboard_tests", "Quarantined by"),
      type: :option,
      options: [:tuist | Enum.map(quarantine_actors, & &1.id)],
      options_display_names:
        Map.merge(
          %{tuist: dgettext("dashboard_tests", "Tuist")},
          Map.new(quarantine_actors, fn account -> {account.id, account.name} end)
        ),
      operator: :==,
      value: nil
    }

    base_filters ++ [quarantined_by_filter]
  end

  def handle_params(params, _uri, socket) do
    uri = URI.new!("?" <> URI.encode_query(params))

    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign(:uri, uri)
      |> assign_analytics(params)
      |> assign_quarantined_tests(params)
    }
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("page", "1")

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/quarantined-tests?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.put("page", "1")

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/quarantined-tests?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event(
        "search-quarantined-tests",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query =
      uri.query
      |> Query.put("search", search)
      |> Query.drop("page")

    socket =
      push_patch(
        socket,
        to: "/#{selected_account.name}/#{selected_project.name}/tests/quarantined-tests?#{query}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
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

    {:noreply,
     push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/tests/quarantined-tests?#{query_params}")}
  end

  def handle_info({:test_created, %{name: "test"}}, socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign_analytics(socket.assigns.current_params)
       |> assign_quarantined_tests(socket.assigns.current_params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_quarantined_tests(%{assigns: %{selected_project: project}} = socket, params) do
    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    page = parse_page(params["page"])
    sort_by = validate_sort_by(params["sort_by"])
    sort_order = params["sort_order"] || "desc"
    search = params["search"] || ""

    flop_filters = build_flop_filters(filters, search)

    order_by = [String.to_existing_atom(sort_by)]
    order_directions = [String.to_existing_atom(sort_order)]

    options = %{
      filters: flop_filters,
      order_by: order_by,
      order_directions: order_directions,
      page: page,
      page_size: 20
    }

    {quarantined_tests, quarantined_tests_meta} = Runs.list_quarantined_test_cases(project.id, options)

    socket
    |> assign(:active_filters, filters)
    |> assign(:quarantined_tests, quarantined_tests)
    |> assign(:quarantined_tests_meta, quarantined_tests_meta)
    |> assign(:quarantined_tests_page, page)
    |> assign(:quarantined_tests_sort_by, sort_by)
    |> assign(:quarantined_tests_sort_order, sort_order)
    |> assign(:quarantined_tests_filter, search)
  end

  defp parse_page(nil), do: 1
  defp parse_page(page) when is_binary(page), do: String.to_integer(page)
  defp parse_page(page) when is_integer(page), do: page

  defp validate_sort_by(nil), do: @default_sort_field
  defp validate_sort_by(field) when field in @allowed_sort_fields, do: field
  defp validate_sort_by(_invalid), do: @default_sort_field

  defp build_flop_filters(filters, search) do
    flop_filters = Filter.Operations.convert_filters_to_flop(filters)

    if search == "" do
      flop_filters
    else
      flop_filters ++ [%{field: :name, op: :ilike_and, value: search}]
    end
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [start_datetime: start_datetime, end_datetime: end_datetime]

    quarantined_analytics = Analytics.quarantined_tests_analytics(project.id, opts)

    socket
    |> assign(:quarantined_analytics, quarantined_analytics)
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
  end

  defp sort_icon("asc"), do: "square_rounded_arrow_up"
  defp sort_icon("desc"), do: "square_rounded_arrow_down"

  defp toggle_sort_order("asc"), do: "desc"
  defp toggle_sort_order("desc"), do: "asc"

  defp column_sort_patch(assigns, column) do
    new_order =
      if assigns.quarantined_tests_sort_by == column do
        toggle_sort_order(assigns.quarantined_tests_sort_order)
      else
        "desc"
      end

    "?#{assigns.uri.query |> Query.put("sort_by", column) |> Query.put("sort_order", new_order) |> Query.drop("page")}"
  end

  defp sort_by_patch(uri, sort_by) do
    "?#{uri.query |> Query.put("sort_by", sort_by) |> Query.drop("page")}"
  end
end
