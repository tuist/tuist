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
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Test Cases")} · #{slug} · Tuist")
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
        display_name: dgettext("dashboard_tests", "Last Status"),
        type: :option,
        options: ["success", "failure", "skipped"],
        options_display_names: %{
          "success" => dgettext("dashboard_tests", "Passed"),
          "failure" => dgettext("dashboard_tests", "Failed"),
          "skipped" => dgettext("dashboard_tests", "Skipped")
        },
        operator: :==,
        value: nil
      },
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
      },
      %Filter.Filter{
        id: "name",
        field: "name",
        display_name: dgettext("dashboard_tests", "Test Case"),
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
          "/#{selected_account.name}/#{selected_project.name}/tests/test-cases?#{Query.put(uri.query, "analytics-selected-widget", widget)}",
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
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "test_case_run_duration")

    socket =
      push_patch(
        socket,
        to: "/#{selected_account.name}/#{selected_project.name}/tests/test-cases?#{query}",
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
     push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/tests/test-cases?#{query_params}")}
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
    analytics_environment = params["analytics-environment"] || "any"
    selected_duration_type = params["duration-type"] || "avg"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [start_datetime: start_datetime, end_datetime: end_datetime]

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

    analytics_selected_widget = params["analytics-selected-widget"] || "test_case_run_count"

    analytics_chart_data =
      case analytics_selected_widget do
        "test_case_run_count" ->
          %{
            dates: test_case_runs_analytics.dates,
            values: test_case_runs_analytics.values,
            name: dgettext("dashboard_tests", "Test case runs"),
            value_formatter: "{value}"
          }

        "failed_test_case_run_count" ->
          %{
            dates: failed_test_case_runs_analytics.dates,
            values: failed_test_case_runs_analytics.values,
            name: dgettext("dashboard_tests", "Failed test case runs"),
            value_formatter: "{value}"
          }

        "test_case_run_duration" ->
          {values, name} =
            case selected_duration_type do
              "p99" ->
                {test_case_runs_duration_analytics.p99_values, dgettext("dashboard_tests", "p99 test case run duration")}

              "p90" ->
                {test_case_runs_duration_analytics.p90_values, dgettext("dashboard_tests", "p90 test case run duration")}

              "p50" ->
                {test_case_runs_duration_analytics.p50_values, dgettext("dashboard_tests", "p50 test case run duration")}

              _ ->
                {test_case_runs_duration_analytics.values, dgettext("dashboard_tests", "Avg. test case run duration")}
            end

          %{
            dates: test_case_runs_duration_analytics.dates,
            values: values,
            name: name,
            value_formatter: "fn:formatMilliseconds"
          }
      end

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
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

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_tests", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_tests", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_tests", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_tests", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_tests", "since last month")

  defp analytics_environment_label("any"), do: dgettext("dashboard_tests", "Any")
  defp analytics_environment_label("local"), do: dgettext("dashboard_tests", "Local")
  defp analytics_environment_label("ci"), do: dgettext("dashboard_tests", "CI")

  @allowed_sort_fields ~w(name last_duration avg_duration last_ran_at)
  @default_sort_field "last_ran_at"

  defp assign_test_cases(%{assigns: %{selected_project: project}} = socket, params) do
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
