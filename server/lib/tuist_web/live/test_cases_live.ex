defmodule TuistWeb.TestCasesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Test Cases")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("test-cases"))
      |> assign(:available_filters, define_filters(project))

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  defp define_filters(project) do
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
        display_name: module_label(project),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "suite_name",
        field: "suite_name",
        display_name: suite_label(project),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "test_case_trait",
        field: :test_case_trait,
        display_name: dgettext("dashboard_tests", "Test case"),
        type: :option,
        options: [:flaky, :muted, :skipped],
        options_display_names: %{
          flaky: dgettext("dashboard_tests", "Flaky"),
          muted: dgettext("dashboard_tests", "Muted"),
          skipped: dgettext("dashboard_tests", "Skipped")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_test_cases(params)
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
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-cases?#{updated_params}"
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
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-cases?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)
    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:analytics_selected_widget, widget)
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    {:noreply,
     if socket.assigns.analytics_chart_data.ok? do
       chart_data =
         analytics_chart_data(
           widget,
           socket.assigns.selected_duration_type,
           socket.assigns.test_case_runs_analytics.result,
           socket.assigns.failed_test_case_runs_analytics.result,
           socket.assigns.test_case_runs_duration_analytics.result,
           socket.assigns.test_cases_count_analytics.result
         )

       assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})
     else
       socket
     end}
  end

  def handle_event("select_duration_type", %{"type" => type}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "test_case_run_duration")

    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:selected_duration_type, type)
      |> assign(:analytics_selected_widget, "test_case_run_duration")
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    {:noreply,
     if socket.assigns.analytics_chart_data.ok? do
       chart_data =
         analytics_chart_data(
           "test_case_run_duration",
           type,
           socket.assigns.test_case_runs_analytics.result,
           socket.assigns.failed_test_case_runs_analytics.result,
           socket.assigns.test_case_runs_duration_analytics.result,
           socket.assigns.test_cases_count_analytics.result
         )

       assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})
     else
       socket
     end}
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

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
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

    analytics_selected_widget = params["analytics-selected-widget"] || "test_case_run_count"

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_environment_label, analytics_environment_label(analytics_environment))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_duration_type, selected_duration_type)
    |> assign(:uri, uri)
    |> assign_async(
      [
        :test_case_runs_analytics,
        :failed_test_case_runs_analytics,
        :test_case_runs_duration_analytics,
        :test_cases_count_analytics,
        :analytics_chart_data
      ],
      fn ->
        test_case_runs_analytics = Analytics.test_case_run_analytics(project.id, opts)

        failed_test_case_runs_analytics =
          Analytics.test_case_run_analytics(project.id, Keyword.put(opts, :status, "failure"))

        test_case_runs_duration_analytics =
          Analytics.test_case_run_duration_analytics(project.id, opts)

        test_cases_count_analytics = Analytics.test_cases_count_analytics(project.id, opts)

        {:ok,
         %{
           test_case_runs_analytics: test_case_runs_analytics,
           failed_test_case_runs_analytics: failed_test_case_runs_analytics,
           test_case_runs_duration_analytics: test_case_runs_duration_analytics,
           test_cases_count_analytics: test_cases_count_analytics,
           analytics_chart_data:
             analytics_chart_data(
               analytics_selected_widget,
               selected_duration_type,
               test_case_runs_analytics,
               failed_test_case_runs_analytics,
               test_case_runs_duration_analytics,
               test_cases_count_analytics
             )
         }}
      end
    )
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp analytics_chart_data(
         analytics_selected_widget,
         selected_duration_type,
         test_case_runs_analytics,
         failed_test_case_runs_analytics,
         test_case_runs_duration_analytics,
         test_cases_count_analytics
       ) do
    chart_data =
      case analytics_selected_widget do
        "test_cases_count" ->
          %{
            dates: test_cases_count_analytics.dates,
            values: test_cases_count_analytics.values,
            name: dgettext("dashboard_tests", "Test cases"),
            value_formatter: "{value}",
            color: "var:noora-chart-tertiary"
          }

        "test_case_run_count" ->
          %{
            dates: test_case_runs_analytics.dates,
            values: test_case_runs_analytics.values,
            name: dgettext("dashboard_tests", "Test case runs"),
            value_formatter: "{value}",
            color: "var:noora-chart-primary"
          }

        "failed_test_case_run_count" ->
          %{
            dates: failed_test_case_runs_analytics.dates,
            values: failed_test_case_runs_analytics.values,
            name: dgettext("dashboard_tests", "Failed test case runs"),
            value_formatter: "{value}",
            color: "var:noora-chart-destructive"
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
            value_formatter: "fn:formatMilliseconds",
            color: "var:noora-chart-secondary"
          }
      end

    Map.put(
      chart_data,
      :grid_left,
      if(Enum.max(chart_data.values, fn -> 0 end) >= 1_000_000, do: "0.8%", else: "0.4%")
    )
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

    socket
    |> assign(:active_filters, filters)
    |> assign(:test_cases_current_page, page)
    |> assign(:test_cases_sort_by, sort_by)
    |> assign(:test_cases_sort_order, sort_order)
    |> assign(:test_cases_filter, search)
    |> assign_async(
      :test_cases_page,
      fn ->
        {test_cases, test_cases_meta} = Tests.list_test_cases(project.id, options)
        {:ok, %{test_cases_page: %{test_cases: test_cases, meta: test_cases_meta}}}
      end,
      reset: true
    )
  end

  defp parse_page(nil), do: 1
  defp parse_page(page) when is_binary(page), do: String.to_integer(page)
  defp parse_page(page) when is_integer(page), do: page

  defp validate_sort_by(nil), do: @default_sort_field
  defp validate_sort_by(field) when field in @allowed_sort_fields, do: field
  defp validate_sort_by(_invalid), do: @default_sort_field

  defp build_flop_filters(filters, search) do
    flop_filters =
      filters
      |> Filter.Operations.convert_filters_to_flop()
      |> Enum.map(&convert_trait_filter/1)

    if search == "" do
      flop_filters
    else
      flop_filters ++ [%{field: :name, op: :ilike_and, value: search}]
    end
  end

  defp convert_trait_filter(%{field: :test_case_trait, value: :flaky} = filter) do
    %{filter | field: :is_flaky, value: true}
  end

  defp convert_trait_filter(%{field: :test_case_trait, value: :muted} = filter) do
    %{filter | field: :state, value: "muted"}
  end

  defp convert_trait_filter(%{field: :test_case_trait, value: :skipped} = filter) do
    %{filter | field: :state, value: "skipped"}
  end

  defp convert_trait_filter(filter), do: filter

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
