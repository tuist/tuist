defmodule TuistWeb.TestCasesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{gettext("Test Cases")} · #{slug} · Tuist")
      |> assign(:available_filters, define_filters())

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  defp define_filters do
    [
      %Filter.Filter{
        id: "last_status",
        field: "last_status",
        display_name: gettext("Last Status"),
        type: :option,
        options: ["success", "failure", "skipped"],
        options_display_names: %{
          "success" => gettext("Passed"),
          "failure" => gettext("Failed"),
          "skipped" => gettext("Skipped")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "module_name",
        field: "module_name",
        display_name: gettext("Module"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "suite_name",
        field: "suite_name",
        display_name: gettext("Suite"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "name",
        field: "name",
        display_name: gettext("Test Case"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  def handle_params(params, _uri, socket) do
    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_test_cases(params)
    }
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-cases?#{updated_params}"
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
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-cases?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event(
        "select_widget",
        %{"widget" => widget},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/tests/test-cases?#{Query.put(uri.query, "analytics_selected_widget", widget)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "select_duration_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query =
      uri.query
      |> Query.put("duration_type", type)
      |> Query.put("analytics_selected_widget", "test_case_run_duration")

    socket =
      push_patch(
        socket,
        to: "/#{selected_account.name}/#{selected_project.name}/tests/test-cases?#{query}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "search-test-cases",
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
        to: "/#{selected_account.name}/#{selected_project.name}/tests/test-cases?#{query}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_info({:test_created, %{name: "test"}}, socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign_analytics(socket.assigns.current_params)
       |> assign_test_cases(socket.assigns.current_params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    date_range = date_range(params)
    analytics_environment = analytics_environment(params)
    selected_duration_type = params["duration_type"] || "avg"

    opts = [
      start_date: start_date(date_range)
    ]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    uri = URI.new!("?" <> URI.encode_query(params))

    [test_case_runs_analytics, failed_test_case_runs_analytics, test_case_runs_duration_analytics] =
      Task.await_many(
        [
          Task.async(fn -> Analytics.test_case_run_analytics(project.id, opts) end),
          Task.async(fn -> Analytics.test_case_run_analytics(project.id, Keyword.put(opts, :status, "failure")) end),
          Task.async(fn -> Analytics.test_case_run_duration_analytics(project.id, opts) end)
        ],
        30_000
      )

    analytics_selected_widget = analytics_selected_widget(params)

    analytics_chart_data =
      case analytics_selected_widget do
        "test_case_run_count" ->
          %{
            dates: test_case_runs_analytics.dates,
            values: test_case_runs_analytics.values,
            name: gettext("Test case runs"),
            value_formatter: "{value}"
          }

        "failed_test_case_run_count" ->
          %{
            dates: failed_test_case_runs_analytics.dates,
            values: failed_test_case_runs_analytics.values,
            name: gettext("Failed test case runs"),
            value_formatter: "{value}"
          }

        "test_case_run_duration" ->
          {values, name} =
            case selected_duration_type do
              "p99" ->
                {test_case_runs_duration_analytics.p99_values, gettext("p99 test case run duration")}

              "p90" ->
                {test_case_runs_duration_analytics.p90_values, gettext("p90 test case run duration")}

              "p50" ->
                {test_case_runs_duration_analytics.p50_values, gettext("p50 test case run duration")}

              _ ->
                {test_case_runs_duration_analytics.values, gettext("Avg. test case run duration")}
            end

          %{
            dates: test_case_runs_duration_analytics.dates,
            values: values,
            name: name,
            value_formatter: "fn:formatMilliseconds"
          }
      end

    socket
    |> assign(:analytics_date_range, date_range)
    |> assign(:analytics_trend_label, analytics_trend_label(date_range))
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_environment_label, analytics_environment_label(analytics_environment))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_duration_type, selected_duration_type)
    |> assign(:test_case_runs_analytics, test_case_runs_analytics)
    |> assign(:failed_test_case_runs_analytics, failed_test_case_runs_analytics)
    |> assign(:test_case_runs_duration_analytics, test_case_runs_duration_analytics)
    |> assign(:analytics_chart_data, analytics_chart_data)
    |> assign(:uri, uri)
  end

  defp start_date("last_12_months"), do: Date.add(DateTime.utc_now(), -365)
  defp start_date("last_30_days"), do: Date.add(DateTime.utc_now(), -30)
  defp start_date("last_7_days"), do: Date.add(DateTime.utc_now(), -7)

  defp analytics_trend_label("last_7_days"), do: gettext("since last week")
  defp analytics_trend_label("last_12_months"), do: gettext("since last year")
  defp analytics_trend_label(_), do: gettext("since last month")

  defp analytics_environment_label("any"), do: gettext("Any")
  defp analytics_environment_label("local"), do: gettext("Local")
  defp analytics_environment_label("ci"), do: gettext("CI")

  defp date_range(params) do
    params["analytics_date_range"] || "last_30_days"
  end

  defp analytics_environment(params) do
    params["analytics_environment"] || "any"
  end

  defp analytics_selected_widget(params) do
    params["analytics_selected_widget"] || "test_case_run_count"
  end

  defp assign_test_cases(%{assigns: %{selected_project: project}} = socket, params) do
    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    page = parse_page(params["page"])
    sort_by = params["sort_by"] || "last_ran_at"
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

    {test_cases, test_cases_meta} = Runs.list_test_cases(project.id, options)

    socket
    |> assign(:active_filters, filters)
    |> assign(:test_cases, test_cases)
    |> assign(:test_cases_meta, test_cases_meta)
    |> assign(:test_cases_page, page)
    |> assign(:test_cases_sort_by, sort_by)
    |> assign(:test_cases_sort_order, sort_order)
    |> assign(:test_cases_filter, search)
  end

  defp parse_page(nil), do: 1
  defp parse_page(page) when is_binary(page), do: String.to_integer(page)
  defp parse_page(page) when is_integer(page), do: page

  defp build_flop_filters(filters, search) do
    flop_filters = Filter.Operations.convert_filters_to_flop(filters)

    if search == "" do
      flop_filters
    else
      flop_filters ++ [%{field: :name, op: :ilike_and, value: search}]
    end
  end

  defp sort_icon("asc"), do: "square_rounded_arrow_up"
  defp sort_icon("desc"), do: "square_rounded_arrow_down"

  defp toggle_sort_order("asc"), do: "desc"
  defp toggle_sort_order("desc"), do: "asc"

  defp column_sort_patch(assigns, column) do
    new_order =
      if assigns.test_cases_sort_by == column do
        toggle_sort_order(assigns.test_cases_sort_order)
      else
        "desc"
      end

    "?#{assigns.uri.query |> Query.put("sort_by", column) |> Query.put("sort_order", new_order) |> Query.drop("page")}"
  end

  defp sort_by_patch(uri, sort_by) do
    "?#{uri.query |> Query.put("sort_by", sort_by) |> Query.drop("page")}"
  end
end
