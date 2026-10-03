defmodule TuistWeb.GradleTasksLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Helpers.GradleTask
  import TuistWeb.Runs.ProjectWithTags
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Gradle.TaskAnalytics
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.ModulesLive

  @sort_fields ~w(cumulative_duration_ms misses executions p50_duration_ms p90_duration_ms p99_duration_ms hit_rate)

  @duration_metrics ~w(avg_duration_ms p90_duration_ms p50_duration_ms p99_duration_ms)
  @widgets ~w(tasks executions hit_rate task_duration)
  @date_params ~w(analytics-date-range analytics-start-date analytics-end-date)

  def mount(_params, _session, socket), do: {:ok, assign(socket, :available_filters, define_filters())}

  def handle_params(params, uri, socket) do
    params = Map.filter(params, fn {_key, value} -> is_binary(value) end)

    name = params["name"]
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    %{preset: preset, period: new_period} = DatePicker.date_picker_params(params, "analytics")

    period =
      if socket.assigns[:date_params] == Map.take(params, @date_params),
        do: socket.assigns.analytics_period,
        else: new_period

    selected_widget = widget_selection(params)

    {start_at, end_at} = period
    opts = query_opts(params, active_filters, start_at, end_at)

    project_id = socket.assigns.selected_project.id

    title = name || dgettext("dashboard_gradle", "Tasks")

    key = {name, opts}

    socket =
      socket
      |> assign(:name, name)
      |> assign(:params, params)
      |> assign(:uri, %{URI.parse(uri) | query: URI.encode_query(query_params(params))})
      |> assign(:active_filters, active_filters)
      |> assign(
        :analytics_environment,
        if(params["analytics-environment"] in ~w(ci local), do: params["analytics-environment"], else: "any")
      )
      |> assign(:date_params, Map.take(params, @date_params))
      |> assign(:analytics_selected_widget, selected_widget)
      |> assign(:analytics_duration_metric, duration_selection(params))
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_trend_label, analytics_trend_label(preset))
      |> assign(:analytics_period, period)
      |> assign(:sort_by, if(params["sort"] in @sort_fields, do: params["sort"], else: "cumulative_duration_ms"))
      |> assign(:sort_order, if(params["order"] == "asc", do: "asc", else: "desc"))
      |> assign(:search, params["q"] || "")
      |> assign(:execution_search, params["execution-search"] || "")
      |> assign(:execution_sort, execution_sort(params))
      |> assign(:execution_order, execution_order(params))
      |> assign(:head_title, "#{title} · Builds · Tuist")

    socket =
      if socket.assigns[:query_key] == key do
        socket
      else
        socket
        |> assign(:query_key, key)
        |> assign_async(:analytics, fn -> load_analytics(project_id, name, opts) end, reset: true)
      end

    {:noreply, socket}
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  defp duration_selection(params) do
    case params["analytics-duration-metric"] do
      metric when metric in @duration_metrics -> metric
      _ -> "p90_duration_ms"
    end
  end

  defp widget_selection(params) do
    case params["analytics-selected-widget"] do
      "cumulative_duration_ms" -> "task_duration"
      "tasks" when is_map_key(params, "name") -> "executions"
      metric when metric in ~w(hits misses) -> "hit_rate"
      widget when widget in @widgets -> widget
      _ -> "executions"
    end
  end

  defp query_opts(params, active_filters, start_at, end_at) do
    opts = [
      start_datetime: start_at,
      end_datetime: end_at,
      filters: environment_filters(params) ++ Filter.Operations.convert_filters_to_flop(active_filters),
      execution_search: params["execution-search"] || "",
      execution_sort: params["execution-sort"] || "ran_at",
      execution_order: params["execution-order"] || "desc",
      execution_page: execution_page(params["execution-page"])
    ]

    Enum.reduce(~w(root_project_name build_path task_type name), opts, fn key, acc ->
      case params[key] do
        nil -> acc
        value -> Keyword.put(acc, if(key == "name", do: :task_path, else: String.to_existing_atom(key)), value)
      end
    end)
  end

  defp execution_sort(params), do: if(params["execution-sort"] == "duration", do: "duration", else: "ran_at")
  defp execution_order(params), do: if(params["execution-order"] == "asc", do: "asc", else: "desc")

  defp execution_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp execution_page(_), do: 1

  defp execution_sort_patch(assigns, sort) do
    order = if assigns.execution_sort == sort and assigns.execution_order == "desc", do: "asc", else: "desc"
    patch(assigns, %{"execution-sort" => sort, "execution-order" => order, "execution-page" => nil})
  end

  defp define_filters do
    [
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: dgettext("dashboard_gradle", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  defp environment_filters(params) do
    case params["analytics-environment"] do
      "ci" -> [%{field: :is_ci, op: :==, value: :ci}]
      "local" -> [%{field: :is_ci, op: :==, value: :local}]
      _ -> []
    end
  end

  defp environment_label("ci"), do: dgettext("dashboard_gradle", "CI")
  defp environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  defp environment_label(_), do: dgettext("dashboard_gradle", "Any")

  defp load_analytics(project_id, name, opts) do
    result = if name, do: %{rows: [], truncated: false}, else: TaskAnalytics.list(project_id, opts)

    history =
      if name do
        TaskAnalytics.task_executions(project_id, name, opts)
      else
        %{rows: [], page: 1, total_pages: 1}
      end

    {:ok,
     %{
       analytics: %{
         rows: result.rows,
         metrics: TaskAnalytics.analytics(project_id, opts),
         history: history,
         truncated: result.truncated
       }
     }}
  end

  def handle_event("search_task_executions", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"execution-search" => search, "execution-page" => nil}))}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"q" => q, "after" => nil, "before" => nil}))}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    if Enum.any?(socket.assigns.available_filters, &(&1.id == filter_id)) do
      params = Filter.Operations.add_filter_to_query(filter_id, socket)

      {:noreply,
       socket
       |> push_patch(to: "#{socket.assigns.uri.path}?#{URI.encode_query(params)}")
       |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
       |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: "#{socket.assigns.uri.path}?#{URI.encode_query(updated_params)}")
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event("select_duration_metric", %{"type" => metric}, socket) when metric in @duration_metrics do
    {:noreply,
     socket
     |> push_patch(
       to:
         patch(socket.assigns, %{
           "analytics-duration-metric" => metric,
           "analytics-selected-widget" => "task_duration"
         }),
       replace: true
     )
     |> push_event("close-dropdown", %{all: true})}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) when widget in @widgets do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"analytics-selected-widget" => widget}), replace: true)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_at, "end" => end_at}, "preset" => preset},
        socket
      ) do
    {:noreply,
     push_patch(socket,
       to:
         patch(socket.assigns, %{
           "analytics-date-range" => preset,
           "analytics-start-date" => start_at,
           "analytics-end-date" => end_at,
           "after" => nil,
           "before" => nil
         })
     )}
  end

  defp patch(assigns, changes) do
    query =
      assigns.params
      |> query_params()
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> URI.encode_query()

    "#{assigns.uri.path}?#{query}"
  end

  defp sort_patch(assigns, field) do
    order = if assigns.sort_by == field and assigns.sort_order == "desc", do: "asc", else: "desc"
    patch(assigns, %{"sort" => field, "order" => order, "after" => nil, "before" => nil})
  end

  defp page(assigns) do
    rows =
      Enum.filter(
        assigns.analytics.result.rows,
        &String.contains?(String.downcase(&1.name), String.downcase(assigns.search))
      )

    {known, unknown} = Enum.split_with(rows, &(not is_nil(Map.get(&1, String.to_existing_atom(assigns.sort_by)))))
    field = String.to_existing_atom(assigns.sort_by)
    direction = if assigns.sort_order == "asc", do: 1, else: -1
    rows = Enum.sort_by(known, &{Map.fetch!(&1, field) * direction, &1.id}) ++ Enum.sort_by(unknown, & &1.id)
    # Use identity, including the build and task type, as the pagination cursor.
    rows = rows |> Enum.map(&Map.put(&1, :name_for_display, &1.name)) |> Enum.map(&Map.put(&1, :name, &1.id))
    page = ModulesLive.page_of(rows, assigns.params["after"], assigns.params["before"])
    Map.put(page, :rows, Enum.map(page.rows, &Map.put(&1, :name, &1.name_for_display)))
  end

  defp query_params(params) do
    Map.take(params, @date_params ++ ~w(analytics-environment analytics-duration-metric analytics-selected-widget
      sort order q after before execution-search execution-sort execution-order execution-page
      root_project_name build_path task_type filter_git_branch_op filter_git_branch_val))
  end

  defp cohort_params(params) do
    Map.filter(params, fn {key, _} ->
      String.starts_with?(key, "filter_") or key in @date_params or
        key in ~w(analytics-selected-widget analytics-duration-metric analytics-environment)
    end)
  end

  defp entity_path(assigns, row) do
    base =
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/tasks/#{URI.encode(row.name, &URI.char_unreserved?/1)}"

    query =
      assigns.params
      |> cohort_params()
      |> Map.merge(%{
        "build_path" => row.build_path,
        "root_project_name" => row.root_project_name,
        "task_type" => row.task_type
      })
      |> URI.encode_query()

    "#{base}?#{query}"
  end

  defp list_path(assigns) do
    "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/tasks?#{URI.encode_query(cohort_params(assigns.params))}"
  end

  defp execution_path(assigns, execution),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/build-runs/#{execution.build_id}/tasks/#{execution.id}"

  defp duration(nil), do: "—"
  defp duration(value), do: DateFormatter.format_duration_from_milliseconds(round(value))
  defp percent(nil), do: "—"
  defp percent(value) when value == trunc(value), do: "#{trunc(value)}%"
  defp percent(value), do: "#{value}%"

  defp metrics(name, duration_metric) do
    Enum.reject(
      [
        %{
          id: "tasks",
          field: :tasks,
          color: "primary",
          title: dgettext("dashboard_gradle", "Tasks"),
          description:
            dgettext(
              "dashboard_gradle",
              "Distinct tasks observed in matching builds. Each chart point counts distinct tasks in that interval."
            )
        },
        %{
          id: "executions",
          field: :executions,
          color: "secondary",
          title: dgettext("dashboard_gradle", "Executions"),
          description: dgettext("dashboard_gradle", "Tasks that ran instead of reusing outputs.")
        },
        %{
          id: "hit_rate",
          field: :hit_rate,
          color: "primary",
          title: dgettext("dashboard_gradle", "Cache hit rate"),
          description:
            dgettext(
              "dashboard_gradle",
              "Remote cache hits divided by hits and confirmed misses. Local cache hits and up-to-date tasks are excluded."
            )
        },
        duration_metric(duration_metric)
      ],
      &(name && &1.id == "tasks")
    )
  end

  defp duration_options do
    [
      %{field: :avg_duration_ms, color: "secondary", title: dgettext("dashboard_gradle", "Avg. task duration")},
      %{field: :p90_duration_ms, color: "p90", title: dgettext("dashboard_gradle", "p90 task duration")},
      %{field: :p50_duration_ms, color: "p50", title: dgettext("dashboard_gradle", "p50 task duration")},
      %{field: :p99_duration_ms, color: "p99", title: dgettext("dashboard_gradle", "p99 task duration")}
    ]
  end

  defp duration_metric(selection) do
    duration_options()
    |> Enum.find(&(Atom.to_string(&1.field) == selection))
    |> Map.merge(%{
      id: "task_duration",
      description:
        if(selection == "avg_duration_ms",
          do: dgettext("dashboard_gradle", "Average task duration across executions in the selected period."),
          else: dgettext("dashboard_gradle", "Task duration percentile across executions in the selected period.")
        )
    })
  end

  defp metric_value(%{id: "hit_rate"}, value), do: percent(value)
  defp metric_value(%{id: "task_duration"}, value), do: duration(value)
  defp metric_value(_metric, value), do: format_number(value)

  defp metric_trend(%{id: "hit_rate"}, total, previous) when is_number(total) and is_number(previous),
    do: total - previous

  defp metric_trend(_metric, total, previous) when is_number(total) and is_number(previous) and previous > 0,
    do: (total - previous) / previous * 100

  defp metric_trend(_metric, total, previous) when is_number(total) and previous == 0, do: total * 1.0
  defp metric_trend(_metric, _total, _previous), do: nil

  defp metric_trend_label(%{id: "hit_rate"}, total, previous) when is_number(total) and is_number(previous) do
    difference = Float.round((total - previous) * 1.0, 1)

    if difference == 0,
      do: nil,
      else: dgettext("dashboard_gradle", "%{change} pp", change: "#{if difference > 0, do: "+"}#{difference}")
  end

  defp metric_trend_label(metric, total, previous) when is_number(total) and total != 0 and previous == 0 do
    if total > 0, do: "+#{metric_value(metric, total)}", else: metric_value(metric, total)
  end

  defp metric_trend_label(_metric, _total, _previous), do: nil

  defp metric_trend_type(%{id: "hit_rate"}), do: :regular
  defp metric_trend_type(%{id: "task_duration"}), do: :inverse
  defp metric_trend_type(_), do: :neutral

  defp chart_series(%{id: "task_duration"}, points) do
    Enum.map(
      [
        {:avg_duration_ms, dgettext("dashboard", "Avg."), "secondary"},
        {:p99_duration_ms, dgettext("dashboard_gradle", "p99"), "p99"},
        {:p90_duration_ms, dgettext("dashboard_gradle", "p90"), "p90"},
        {:p50_duration_ms, dgettext("dashboard_gradle", "p50"), "p50"}
      ],
      fn {field, title, color} -> line_series(title, field, color, points) end
    )
  end

  defp chart_series(metric, points), do: [line_series(metric.title, metric.field, metric.color, points)]

  defp line_series(title, field, color, points) do
    duration? = Atom.to_string(field) in @duration_metrics
    sampled? = duration? or field == :hit_rate

    %{
      name: title,
      type: "line",
      color: "var:noora-chart-#{color}",
      data: Enum.map(points, &[&1.date, if(duration? and &1.executions == 0, do: nil, else: Map.fetch!(&1, field))]),
      connectNulls: sampled?,
      smooth: 0.1,
      symbol: if(sampled?, do: "circle", else: "none"),
      symbolSize: 4
    }
  end

  defp chart_options(metric, analytics) do
    formatter =
      case metric.id do
        "task_duration" -> "fn:formatMilliseconds"
        "hit_rate" -> "{value}%"
        _ -> "{value}"
      end

    dates = Enum.map(analytics.points, & &1.date)
    show_legend = metric.id == "task_duration"

    %{
      grid: %{left: "0.4%", right: "3%", bottom: if(show_legend, do: "18%", else: "5%"), top: "5%", containLabel: true},
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        max: if(metric.id == "hit_rate", do: 100),
        interval: if(metric.id == "hit_rate", do: 25),
        splitNumber: 4,
        minInterval: if(metric.id == "task_duration", do: 0, else: 1),
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
      },
      tooltip: %{valueFormat: formatter, dateFormat: if(analytics.period == :hour, do: "hour", else: "date")},
      legend: %{
        show: show_legend,
        left: "left",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-secondary",
          fontFamily: "monospace",
          fontWeight: 400,
          fontSize: 10,
          lineHeight: 12
        },
        icon: "roundRect",
        itemWidth: 8,
        itemHeight: 4
      }
    }
  end

  defp sort_label(field), do: Map.new(sort_options())[field]

  defp sort_options do
    [
      {"cumulative_duration_ms", dgettext("dashboard_gradle", "Cumulative time")},
      {"executions", dgettext("dashboard_gradle", "Executions")},
      {"misses", dgettext("dashboard_gradle", "Misses")},
      {"hit_rate", dgettext("dashboard_gradle", "Hit rate")},
      {"p50_duration_ms", dgettext("dashboard_gradle", "p50 duration")},
      {"p90_duration_ms", dgettext("dashboard_gradle", "p90 duration")},
      {"p99_duration_ms", dgettext("dashboard_gradle", "p99 duration")}
    ]
  end

  defp cache_badge_label(:not_cacheable), do: dgettext("dashboard_gradle", "Not cacheable")
  defp cache_badge_label(:unknown), do: dgettext("dashboard_gradle", "Unknown cacheability")
end
