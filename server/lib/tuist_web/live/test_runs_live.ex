defmodule TuistWeb.TestRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Tests.Coverage
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"
    coverage_enabled = FeatureFlags.xcode_coverage_enabled?(account)

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Test Runs")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("test-runs"))
      |> assign(:coverage_enabled, coverage_enabled)
      |> assign(:available_filters, define_filters(project, coverage_enabled))

    {:ok, socket}
  end

  defp define_filters(project, coverage_enabled) do
    base = [
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_tests", "Status"),
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
        id: "git_branch",
        field: :git_branch,
        display_name: dgettext("dashboard_tests", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]

    coverage =
      if coverage_enabled do
        [
          %Filter.Filter{
            id: "coverage",
            field: :coverage,
            display_name: dgettext("dashboard_tests", "Coverage"),
            type: :option,
            options: ["any", "full", "partial"],
            options_display_names: %{
              "any" => dgettext("dashboard_tests", "Any"),
              "full" => dgettext("dashboard_tests", "Full"),
              "partial" => dgettext("dashboard_tests", "Partial")
            },
            operator: :==,
            value: nil
          }
        ]
      else
        []
      end

    organization =
      if Accounts.organization?(project.account) do
        {:ok, organization} = Accounts.get_organization_by_id(project.account.organization_id)

        users = Accounts.get_organization_members(organization)

        [
          %Filter.Filter{
            id: "ran_by",
            field: :ran_by,
            display_name: dgettext("dashboard_tests", "Ran by"),
            type: :option,
            searchable: true,
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

    base ++ coverage ++ organization
  end

  def handle_params(_params, uri, socket) do
    params = uri |> Query.query_params() |> Query.clear_cursors_on_initial_load(socket.assigns)

    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_test_runs(params)
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
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-runs?#{updated_params}"
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
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-runs?#{updated_query_params}"
     )
     # There's a DOM reconciliation bug where the dropdown closes and then reappears somewhere else on the page. To remedy, just nuke it entirely.
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

    if socket.assigns.test_runs_analytics.ok? do
      chart_data =
        analytics_chart_data(
          widget,
          socket.assigns.selected_duration_type,
          socket.assigns.test_runs_analytics.result,
          socket.assigns.failed_test_runs_analytics.result,
          socket.assigns.test_runs_duration_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_duration_type", %{"type" => type}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "test_run_duration")

    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:selected_duration_type, type)
      |> assign(:analytics_selected_widget, "test_run_duration")
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.test_runs_analytics.ok? do
      chart_data =
        analytics_chart_data(
          "test_run_duration",
          type,
          socket.assigns.test_runs_analytics.result,
          socket.assigns.failed_test_runs_analytics.result,
          socket.assigns.test_runs_duration_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
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

    query_params =
      query_params
      |> Query.drop("before")
      |> Query.drop("after")

    {:noreply,
     push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/tests/test-runs?#{query_params}")}
  end

  def handle_event(
        "search-test-runs",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query =
      uri.query
      |> Query.put("search", search)
      |> Query.drop("before")
      |> Query.drop("after")

    socket =
      push_patch(
        socket,
        to: "/#{selected_account.name}/#{selected_project.name}/tests/test-runs?#{query}",
        replace: true
      )

    {:noreply, socket}
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

    opts = [
      project_id: project.id,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    uri = URI.new!("?" <> URI.encode_query(params))

    analytics_selected_widget = params["analytics-selected-widget"] || "test_run_count"

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
        :test_runs_analytics,
        :failed_test_runs_analytics,
        :test_runs_duration_analytics,
        :analytics_chart_data
      ],
      fn ->
        test_runs_analytics = Analytics.test_run_analytics(project.id, opts)

        failed_test_runs_analytics =
          Analytics.test_run_analytics(project.id, Keyword.put(opts, :status, "failure"))

        test_runs_duration_analytics = Analytics.test_run_duration_analytics(project.id, opts)

        {:ok,
         %{
           test_runs_analytics: test_runs_analytics,
           failed_test_runs_analytics: failed_test_runs_analytics,
           test_runs_duration_analytics: test_runs_duration_analytics,
           analytics_chart_data:
             analytics_chart_data(
               analytics_selected_widget,
               selected_duration_type,
               test_runs_analytics,
               failed_test_runs_analytics,
               test_runs_duration_analytics
             )
         }}
      end
    )
  end

  defp analytics_chart_data(
         analytics_selected_widget,
         selected_duration_type,
         test_runs_analytics,
         failed_test_runs_analytics,
         test_runs_duration_analytics
       ) do
    case analytics_selected_widget do
      "test_run_count" ->
        %{
          dates: test_runs_analytics.dates,
          values: test_runs_analytics.values,
          name: dgettext("dashboard_tests", "Test run count"),
          value_formatter: "{value}"
        }

      "failed_test_run_count" ->
        %{
          dates: failed_test_runs_analytics.dates,
          values: failed_test_runs_analytics.values,
          name: dgettext("dashboard_tests", "Failed run count"),
          value_formatter: "{value}"
        }

      "test_run_duration" ->
        {values, name} =
          case selected_duration_type do
            "p99" ->
              {test_runs_duration_analytics.p99_values, dgettext("dashboard_tests", "p99 test run duration")}

            "p90" ->
              {test_runs_duration_analytics.p90_values, dgettext("dashboard_tests", "p90 test run duration")}

            "p50" ->
              {test_runs_duration_analytics.p50_values, dgettext("dashboard_tests", "p50 test run duration")}

            _ ->
              {test_runs_duration_analytics.values, dgettext("dashboard_tests", "Avg. test run duration")}
          end

        %{
          dates: test_runs_duration_analytics.dates,
          values: values,
          name: name,
          value_formatter: "fn:formatMilliseconds"
        }
    end
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_tests", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_tests", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_tests", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_tests", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_tests", "since last month")

  defp analytics_environment_label("local"), do: dgettext("dashboard_tests", "Local")
  defp analytics_environment_label("ci"), do: dgettext("dashboard_tests", "CI")
  defp analytics_environment_label(_), do: dgettext("dashboard_tests", "Any")

  defp assign_test_runs(%{assigns: %{selected_project: project}} = socket, params) do
    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    search = params["search"] || ""

    {start_datetime, end_datetime} = socket.assigns.analytics_period

    {coverage_filters, run_filters} = Enum.split_with(filters, &(&1.id == "coverage"))

    flop_filters =
      [
        %{field: :project_id, op: :==, value: project.id},
        %{field: :status, op: :!=, value: "in_progress"},
        %{field: :ran_at, op: :>=, value: start_datetime},
        %{field: :ran_at, op: :<=, value: end_datetime}
      ] ++ build_flop_filters(run_filters, search) ++ page_level_environment_filters(socket.assigns)

    options = %{
      filters: flop_filters,
      order_by: [:ran_at],
      order_directions: [:desc]
    }

    options =
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

    {test_runs, test_runs_meta} =
      Tests.list_test_runs(options, project_id: project.id, coverage: coverage_option(coverage_filters))

    coverage_by_run =
      if socket.assigns.coverage_enabled,
        do: Coverage.totals_for_runs(project.id, Enum.map(test_runs, & &1.id)),
        else: %{}

    socket
    |> assign(:active_filters, filters)
    |> assign(:test_runs, test_runs)
    |> assign(:test_runs_meta, test_runs_meta)
    |> assign(:test_runs_filter, search)
    |> assign(:coverage_by_run, coverage_by_run)
  end

  @doc false
  def coverage_label(nil), do: dgettext("dashboard_tests", "No coverage")

  def coverage_label(%{covered_lines: covered, executable_lines: executable}),
    do: "#{Coverage.percentage(covered, executable)}%"

  @doc false
  def coverage_badge_label(%{partial: true}), do: dgettext("dashboard_tests", "P")
  def coverage_badge_label(_totals), do: dgettext("dashboard_tests", "F")

  @doc false
  def coverage_badge_color(%{partial: true}), do: "warning"
  def coverage_badge_color(_totals), do: "success"

  @doc false
  def coverage_title(nil), do: nil

  def coverage_title(%{partial: true}),
    do: dgettext("dashboard_tests", "Partial: the run skipped tests, or a shard did not report its coverage.")

  def coverage_title(_totals), do: dgettext("dashboard_tests", "Full: every test of the run reported its coverage.")

  # `is not` inverts the set the value names, so "is not Full" leaves the
  # partial runs and the ones that gathered no coverage.
  defp coverage_option([%{value: value, operator: operator} | _]) when value in ["full", "partial", "any"] do
    {if(operator == :!=, do: :not_in, else: :in), String.to_existing_atom(value)}
  end

  defp coverage_option(_), do: nil

  defp build_flop_filters(filters, search) do
    {ran_by, filters} = Enum.split_with(filters, &(&1.id == "ran_by"))

    flop_filters = Filter.Operations.convert_filters_to_flop(filters)

    ran_by_flop_filters =
      Enum.flat_map(ran_by, fn
        %{value: :ci, operator: op} ->
          [%{field: :is_ci, op: op, value: true}]

        %{value: value, operator: :==} when not is_nil(value) ->
          [
            %{field: :is_ci, op: :==, value: false},
            %{field: :account_id, op: :==, value: value}
          ]

        %{value: value, operator: op} when not is_nil(value) ->
          [%{field: :account_id, op: op, value: value}]

        _ ->
          []
      end)

    search_filters =
      if search == "" do
        []
      else
        [%{field: :scheme, op: :ilike_and, value: search}]
      end

    flop_filters ++ ran_by_flop_filters ++ search_filters
  end

  defp page_level_environment_filters(%{analytics_environment: "ci"}), do: [%{field: :is_ci, op: :==, value: true}]
  defp page_level_environment_filters(%{analytics_environment: "local"}), do: [%{field: :is_ci, op: :==, value: false}]
  defp page_level_environment_filters(_), do: []
end
