defmodule TuistWeb.TestRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias Tuist.Runs.Analytics
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{gettext("Test Runs")} · #{slug} · Tuist")
      |> assign(:available_filters, define_filters(project))

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  defp define_filters(project) do
    base = [
      %Filter.Filter{
        id: "name",
        field: :name,
        display_name: gettext("Command"),
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
          success: gettext("Passed"),
          failure: gettext("Failed")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: gettext("Branch"),
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
            display_name: gettext("Ran by"),
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

  def handle_params(params, _uri, socket) do
    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_test_runs(params)
    }
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

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
    updated_query_params = Filter.Operations.update_filters_in_query(params, socket)

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

  def handle_info({:command_event_created, %{name: "test"}}, socket) do
    # Only update when pagination is inactive
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign_analytics(socket.assigns.current_params)
       |> assign_test_runs(socket.assigns.current_params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    date_range = date_range(params)

    analytics_environment = analytics_environment(params)

    opts = [
      project_id: project.id,
      start_date: start_date(date_range)
    ]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    uri = URI.new!("?" <> URI.encode_query(params))

    analytics_tasks = [
      Task.async(fn -> Analytics.runs_analytics(project.id, "test", opts) end),
      Task.async(fn ->
        Analytics.runs_analytics(project.id, "test", Keyword.put(opts, :status, :failure))
      end),
      Task.async(fn -> Analytics.runs_duration_analytics("test", opts) end)
    ]

    [test_runs_analytics, failed_test_runs_analytics, test_runs_duration_analytics] =
      Task.await_many(analytics_tasks, 10_000)

    analytics_selected_widget = analytics_selected_widget(params)

    analytics_chart_data =
      case analytics_selected_widget do
        "test_run_count" ->
          %{
            dates: test_runs_analytics.dates,
            values: test_runs_analytics.values,
            name: gettext("Test run count"),
            value_formatter: "{value}"
          }

        "failed_test_run_count" ->
          %{
            dates: failed_test_runs_analytics.dates,
            values: failed_test_runs_analytics.values,
            name: gettext("Failed run count"),
            value_formatter: "{value}"
          }

        "test_run_duration" ->
          %{
            dates: test_runs_duration_analytics.dates,
            values:
              Enum.map(
                test_runs_duration_analytics.values,
                &((&1 / 1000) |> Decimal.from_float() |> Decimal.round(1))
              ),
            name: gettext("Avg. test run duration"),
            value_formatter: "fn:formatSeconds"
          }
      end

    socket
    |> assign(
      :analytics_date_range,
      date_range
    )
    |> assign(
      :analytics_trend_label,
      analytics_trend_label(date_range)
    )
    |> assign(
      :analytics_environment,
      analytics_environment
    )
    |> assign(
      :analytics_environment_label,
      analytics_environment_label(analytics_environment)
    )
    |> assign(
      :analytics_date_range,
      date_range
    )
    |> assign(
      :analytics_selected_widget,
      analytics_selected_widget
    )
    |> assign(
      :test_runs_analytics,
      test_runs_analytics
    )
    |> assign(
      :failed_test_runs_analytics,
      failed_test_runs_analytics
    )
    |> assign(
      :test_runs_duration_analytics,
      test_runs_duration_analytics
    )
    |> assign(
      :analytics_chart_data,
      analytics_chart_data
    )
    |> assign(
      :uri,
      uri
    )
  end

  defp start_date("last_12_months"), do: Date.add(DateTime.utc_now(), -365)
  defp start_date("last_30_days"), do: Date.add(DateTime.utc_now(), -30)
  defp start_date("last_7_days"), do: Date.add(DateTime.utc_now(), -7)

  defp analytics_trend_label("last_7_days"), do: gettext("since last week")
  defp analytics_trend_label("last_12_months"), do: gettext("since last year")
  defp analytics_trend_label(_), do: gettext("since last month")

  defp analytics_environment_label("any") do
    gettext("Any")
  end

  defp analytics_environment_label("local") do
    gettext("Local")
  end

  defp analytics_environment_label("ci") do
    gettext("CI")
  end

  defp date_range(params) do
    analytics_date_range = params["analytics_date_range"]

    if is_nil(analytics_date_range) do
      "last_30_days"
    else
      analytics_date_range
    end
  end

  defp analytics_environment(params) do
    analytics_environment = params["analytics_environment"]

    if is_nil(analytics_environment) do
      "any"
    else
      analytics_environment
    end
  end

  defp analytics_selected_widget(params) do
    analytics_selected_widget = params["analytics_selected_widget"]

    if is_nil(analytics_selected_widget) do
      "test_run_count"
    else
      analytics_selected_widget
    end
  end

  defp assign_test_runs(%{assigns: %{selected_project: project}} = socket, params) do
    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    flop_filters = [
      %{field: :project_id, op: :==, value: project.id}
      | build_flop_filters(filters)
    ]

    options = %{
      filters: flop_filters,
      order_by: [:created_at],
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

    {test_runs, test_runs_meta} = CommandEvents.list_test_runs(options)

    socket
    |> assign(:active_filters, filters)
    |> assign(:test_runs, test_runs)
    |> assign(:test_runs_meta, test_runs_meta)
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
end
