defmodule TuistWeb.ShardsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Tuist.Shards.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Shards")} · #{slug} · Tuist")
      |> assign(:available_filters, [
        %Filter.Filter{
          id: "status",
          field: :status,
          display_name: dgettext("dashboard_tests", "Status"),
          type: :option,
          options: ["success", "failure", "in_progress"],
          options_display_names: %{
            "success" => dgettext("dashboard_tests", "Passed"),
            "failure" => dgettext("dashboard_tests", "Failed"),
            "in_progress" => dgettext("dashboard_tests", "In Progress")
          },
          operator: :==,
          value: nil
        },
        %Filter.Filter{
          id: "granularity",
          field: :granularity,
          display_name: dgettext("dashboard_tests", "Granularity"),
          type: :option,
          options: ["module", "suite"],
          options_display_names: %{
            "module" => dgettext("dashboard_tests", "Module"),
            "suite" => dgettext("dashboard_tests", "Suite")
          },
          operator: :==,
          value: nil
        }
      ])

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))

    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign(:uri, uri)
      |> assign_analytics(params)
      |> assign_shard_sessions(params)
    }
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.delete("page")

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/shards?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.delete("page")

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/shards?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event(
        "search-shard-sessions",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query =
      uri.query
      |> Query.put("search", search)
      |> Query.drop("page")

    {:noreply,
     push_patch(
       socket,
       to: "/#{selected_account.name}/#{selected_project.name}/tests/shards?#{query}",
       replace: true
     )}
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

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/tests/shards?#{query_params}")}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)
    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:analytics_selected_widget, widget)
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.shard_runs_analytics.ok? do
      chart_data =
        analytics_chart_data(
          widget,
          socket.assigns.selected_shard_count_type,
          socket.assigns.selected_balance_type,
          socket.assigns.shard_runs_analytics.result,
          socket.assigns.avg_shard_count_analytics.result,
          socket.assigns.shard_balance_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_shard_count_type", %{"type" => type}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("shard-count-type", type)
      |> Query.put("analytics-selected-widget", "avg_shard_count")

    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:selected_shard_count_type, type)
      |> assign(:analytics_selected_widget, "avg_shard_count")
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.shard_runs_analytics.ok? do
      chart_data =
        analytics_chart_data(
          "avg_shard_count",
          type,
          socket.assigns.selected_balance_type,
          socket.assigns.shard_runs_analytics.result,
          socket.assigns.avg_shard_count_analytics.result,
          socket.assigns.shard_balance_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_balance_type", %{"type" => type}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("balance-type", type)
      |> Query.put("analytics-selected-widget", "avg_shard_balance")

    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:selected_balance_type, type)
      |> assign(:analytics_selected_widget, "avg_shard_balance")
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.shard_runs_analytics.ok? do
      chart_data =
        analytics_chart_data(
          "avg_shard_balance",
          socket.assigns.selected_shard_count_type,
          type,
          socket.assigns.shard_runs_analytics.result,
          socket.assigns.avg_shard_count_analytics.result,
          socket.assigns.shard_balance_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime}} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    analytics_selected_widget = params["analytics-selected-widget"] || "shard_run_count"
    selected_shard_count_type = params["shard-count-type"] || "avg"
    selected_balance_type = params["balance-type"] || "avg"

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, {start_datetime, end_datetime})
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_shard_count_type, selected_shard_count_type)
    |> assign(:selected_balance_type, selected_balance_type)
    |> assign_async(
      [:shard_runs_analytics, :avg_shard_count_analytics, :shard_balance_analytics, :analytics_chart_data],
      fn ->
        shard_runs_analytics = Analytics.shard_session_analytics(project.id, opts)
        avg_shard_count_analytics = Analytics.average_shard_count_analytics(project.id, opts)
        shard_balance_analytics = Analytics.shard_balance_analytics(project.id, opts)

        {:ok,
         %{
           shard_runs_analytics: shard_runs_analytics,
           avg_shard_count_analytics: avg_shard_count_analytics,
           shard_balance_analytics: shard_balance_analytics,
           analytics_chart_data:
             analytics_chart_data(
               analytics_selected_widget,
               selected_shard_count_type,
               selected_balance_type,
               shard_runs_analytics,
               avg_shard_count_analytics,
               shard_balance_analytics
             )
         }}
      end
    )
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp analytics_chart_data(
         analytics_selected_widget,
         selected_shard_count_type,
         selected_balance_type,
         shard_runs_analytics,
         avg_shard_count_analytics,
         shard_balance_analytics
       ) do
    case analytics_selected_widget do
      "shard_run_count" ->
        %{
          dates: shard_runs_analytics.dates,
          values: shard_runs_analytics.values,
          name: dgettext("dashboard_tests", "Sharded run count"),
          value_formatter: "{value}"
        }

      "avg_shard_count" ->
        {values, name} =
          case selected_shard_count_type do
            "p99" ->
              {avg_shard_count_analytics.p99_values, dgettext("dashboard_tests", "p99 shard count")}

            "p90" ->
              {avg_shard_count_analytics.p90_values, dgettext("dashboard_tests", "p90 shard count")}

            "p50" ->
              {avg_shard_count_analytics.p50_values, dgettext("dashboard_tests", "p50 shard count")}

            _ ->
              {avg_shard_count_analytics.values, dgettext("dashboard_tests", "Avg. shard count")}
          end

        %{
          dates: avg_shard_count_analytics.dates,
          values: values,
          name: name,
          value_formatter: "{value}"
        }

      "avg_shard_balance" ->
        {values, name} =
          case selected_balance_type do
            "p99" ->
              {shard_balance_analytics.p99_values, dgettext("dashboard_tests", "p99 shard balance")}

            "p90" ->
              {shard_balance_analytics.p90_values, dgettext("dashboard_tests", "p90 shard balance")}

            "p50" ->
              {shard_balance_analytics.p50_values, dgettext("dashboard_tests", "p50 shard balance")}

            _ ->
              {shard_balance_analytics.values, dgettext("dashboard_tests", "Avg. shard balance")}
          end

        %{
          dates: shard_balance_analytics.dates,
          values: values,
          name: name,
          value_formatter: "{value}%"
        }
    end
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_tests", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_tests", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_tests", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_tests", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_tests", "since last month")

  defp assign_shard_sessions(%{assigns: %{selected_project: project}} = socket, params) do
    page = parse_page(params["page"])
    sort_by = params["sort-by"] || "ran_at"
    sort_order = params["sort-order"] || "desc"
    search = params["search"] || ""

    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    status_filter =
      Enum.find_value(filters, fn
        %{id: "status", value: value} when not is_nil(value) -> value
        _ -> nil
      end)

    granularity_filter =
      Enum.find_value(filters, fn
        %{id: "granularity", value: value} when not is_nil(value) -> value
        _ -> nil
      end)

    {sessions, meta} =
      Analytics.list_shard_sessions(project.id,
        page: page,
        page_size: 20,
        sort_by: sort_by,
        sort_order: sort_order,
        status: status_filter,
        granularity: granularity_filter,
        search: search
      )

    socket
    |> assign(:active_filters, filters)
    |> assign(:shard_sessions, sessions)
    |> assign(:shard_sessions_meta, meta)
    |> assign(:shard_sessions_page, page)
    |> assign(:shard_sessions_sort_by, sort_by)
    |> assign(:shard_sessions_sort_order, sort_order)
    |> assign(:shard_sessions_search, search)
  end

  defp sort_by_patch(uri, sort_by) do
    "?#{uri.query |> Query.put("sort-by", sort_by) |> Query.drop("page")}"
  end

  defp parse_page(nil), do: 1
  defp parse_page(page) when is_binary(page), do: String.to_integer(page)
  defp parse_page(page) when is_integer(page), do: page
end
