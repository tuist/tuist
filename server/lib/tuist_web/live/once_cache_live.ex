defmodule TuistWeb.OnceCacheLive do
  @moduledoc """
  Project-level Once Cache landing page. A one-to-one clone of
  `TuistWeb.BazelCacheLive` — same layout, same `data-part` names so
  the Bazel cache CSS applies verbatim — with data sourced from
  `Tuist.OnceEvents.CacheAnalytics` instead of `Tuist.ReapiCache`.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers
  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.OnceEvents.CacheAnalytics
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    {:ok, assign(socket, :head_title, "#{dgettext("dashboard", "Once Cache")} · #{account.name}/#{project.name} · Tuist")}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project}} = socket) do
    params = Query.query_params(uri)

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:analytics_preset, analytics_preset)
     |> assign(:analytics_period, analytics_period)
     |> assign(:analytics_granularity, time_series_granularity(analytics_period))
     |> assign(:analytics_trend_label, analytics_trend_label(analytics_preset))
     |> assign(:analytics_selected_widget, params["analytics-selected-widget"] || "cache_hit_rate")
     |> assign(:selected_hit_rate_type, selected_hit_rate_type(params["hit-rate-type"]))
     |> assign(:hit_rate_chart_type, hit_rate_chart_type(params["cache-hit-rate-chart-type"]))
     |> assign(:hit_rate_scatter_group_by, scatter_group_by(params["cache-hit-rate-scatter-group-by"]))
     |> assign(:selected_transfer_type, params["transfer-type"] || "combined")
     |> assign(:selected_latency_type, params["latency-type"] || "combined")
     |> assign(:selected_throughput_type, params["throughput-type"] || "combined")
     |> assign_async([:cache_summary, :cache_analytics, :has_any_cache_observations], fn ->
       cache_analytics = CacheAnalytics.analytics(project.id, period_opts(analytics_period))

       {:ok,
        %{
          cache_summary: cache_summary_with_trends(project.id, analytics_period),
          cache_analytics: cache_analytics,
          has_any_cache_observations:
            Enum.any?(cache_analytics.observation_values, &(&1 > 0)) ||
              CacheAnalytics.observations_present?(project.id)
        }}
     end)
     |> assign_hit_rate_scatter(
       hit_rate_chart_type(params["cache-hit-rate-chart-type"]),
       scatter_group_by(params["cache-hit-rate-scatter-group-by"]),
       analytics_period
     )
     |> assign_async(:recent_cache_invocations, fn ->
       {:ok,
        %{
          recent_cache_invocations:
            project.id
            |> CacheAnalytics.recent_invocations(Keyword.put(period_opts(analytics_period), :limit, 40))
            |> Enum.filter(&is_number(&1.cache.hit_rate))
        }}
     end)}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)

    {:noreply,
     socket
     |> assign(:analytics_selected_widget, widget)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event("select_hit_rate_chart_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "cache-hit-rate-chart-type", type)
    type = hit_rate_chart_type(type)

    {:noreply,
     socket
     |> assign(:hit_rate_chart_type, type)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})
     |> assign_hit_rate_scatter(
       type,
       socket.assigns.hit_rate_scatter_group_by,
       socket.assigns.analytics_period
     )}
  end

  def handle_event("select_hit_rate_type", %{"type" => type}, socket),
    do: {:noreply, replace_split_query_param(socket, "hit-rate-type", type)}

  def handle_event("select_transfer_type", %{"type" => type}, socket),
    do: {:noreply, replace_split_query_param(socket, "transfer-type", type)}

  def handle_event("select_latency_type", %{"type" => type}, socket),
    do: {:noreply, replace_split_query_param(socket, "latency-type", type)}

  def handle_event("select_throughput_type", %{"type" => type}, socket),
    do: {:noreply, replace_split_query_param(socket, "throughput-type", type)}

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
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

    {:noreply, push_patch(socket, to: cache_path(socket, query_params))}
  end

  def render(assigns) do
    ~H"""
    <div id="bazel-cache" class="bazel-invocations">
      <.card
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="bazel-cache-analytics-card"
      >
        <:actions>
          <.date_picker
            id="once-cache-date-range-picker"
            name="analytics-date-range"
            presets={date_picker_presets()}
            selected_preset={@analytics_preset}
            period={@analytics_period}
            on_period_change="analytics_period_changed"
            max={Date.utc_today()}
          >
            <:actions>
              <.button
                label={dgettext("dashboard_projects", "Cancel")}
                variant="secondary"
                phx-click={
                  JS.dispatch("phx:date-picker-cancel",
                    detail: %{id: "once-cache-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply", detail: %{id: "once-cache-date-range-picker"})
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="widgets">
          <.percentile_dropdown_widget
            id="once-cache-hit-rate"
            loading={!@cache_summary.ok?}
            title={hit_rate_title(@selected_hit_rate_type)}
            legend_color={percentile_legend_color(@selected_hit_rate_type)}
            description={
              dgettext(
                "dashboard_projects",
                "The percentage of action-cache lookups served from Once's remote cache, measured per run."
              )
            }
            value={
              if @cache_summary.ok?,
                do: hit_rate_value(@cache_summary.result.hit_rate_metrics, @selected_hit_rate_type)
            }
            metrics={
              if @cache_summary.ok?,
                do: hit_rate_metric_values(@cache_summary.result.hit_rate_metrics)
            }
            selected_type={@selected_hit_rate_type}
            event_name="select_hit_rate_type"
            trend_value={
              if @cache_summary.ok?,
                do: hit_rate_trend(@cache_summary.result.hit_rate_trends, @selected_hit_rate_type)
            }
            trend_label={@analytics_trend_label}
            empty={@cache_summary.ok? && @cache_summary.result.hit_rate_metrics.sample_count == 0}
            phx_click="select_widget"
            phx_value_widget="cache_hit_rate"
            selected={@analytics_selected_widget == "cache_hit_rate"}
          />
          <.widget
            id="once-cache-transfer"
            loading={!@cache_summary.ok?}
            title={transfer_title(@selected_transfer_type)}
            legend_color={split_legend_color(@selected_transfer_type, "p50")}
            description={
              dgettext(
                "dashboard_projects",
                "The bytes returned from and accepted by Once's remote cache during the selected period."
              )
            }
            value={
              if @cache_summary.ok?,
                do:
                  ByteFormatter.format_bytes(
                    transfer_value(@cache_summary.result, @selected_transfer_type)
                  )
            }
            trend_value={if @cache_summary.ok?, do: @cache_summary.result.transfer_trend}
            trend_type={:neutral}
            trend_label={@analytics_trend_label}
            empty={@cache_summary.ok? && @cache_summary.result.transfer_bytes == 0}
            phx_click="select_widget"
            phx_value_widget="cache_transfer"
            selected={@analytics_selected_widget == "cache_transfer"}
          >
            <:select>
              <.split_dropdown_item
                selected_type={@selected_transfer_type}
                value="combined"
                event_name="select_transfer_type"
                label={dgettext("dashboard_projects", "Cache transfer")}
                metric={
                  if @cache_summary.ok?,
                    do: ByteFormatter.format_bytes(@cache_summary.result.transfer_bytes)
                }
              />
              <.split_dropdown_item
                selected_type={@selected_transfer_type}
                value="downloads"
                event_name="select_transfer_type"
                label={dgettext("dashboard_projects", "Downloads")}
                metric={
                  if @cache_summary.ok?,
                    do: ByteFormatter.format_bytes(@cache_summary.result.download_bytes)
                }
              />
              <.split_dropdown_item
                selected_type={@selected_transfer_type}
                value="uploads"
                event_name="select_transfer_type"
                label={dgettext("dashboard_projects", "Uploads")}
                metric={
                  if @cache_summary.ok?,
                    do: ByteFormatter.format_bytes(@cache_summary.result.upload_bytes)
                }
              />
            </:select>
          </.widget>
          <.widget
            id="once-cache-latency"
            loading={!@cache_summary.ok?}
            title={latency_title(@selected_latency_type)}
            legend_color={split_legend_color(@selected_latency_type, "p90")}
            description={
              dgettext(
                "dashboard_projects",
                "The average time Once's remote cache spent serving reads and writes during the selected period."
              )
            }
            value={
              if @cache_summary.ok?,
                do:
                  DateFormatter.format_duration_from_milliseconds(
                    latency_value(@cache_summary.result, @selected_latency_type)
                  )
            }
            trend_value={if @cache_summary.ok?, do: @cache_summary.result.latency_trend}
            trend_type={:inverse}
            trend_label={@analytics_trend_label}
            empty={@cache_summary.ok? && @cache_summary.result.latency_ms == 0}
            phx_click="select_widget"
            phx_value_widget="cache_latency"
            selected={@analytics_selected_widget == "cache_latency"}
          >
            <:select>
              <.split_dropdown_item
                selected_type={@selected_latency_type}
                value="combined"
                event_name="select_latency_type"
                label={dgettext("dashboard_projects", "Cache latency")}
                metric={if @cache_summary.ok?, do: format_duration(@cache_summary.result.latency_ms)}
              />
              <.split_dropdown_item
                selected_type={@selected_latency_type}
                value="read"
                event_name="select_latency_type"
                label={dgettext("dashboard_projects", "Read latency")}
                metric={
                  if @cache_summary.ok?, do: format_duration(@cache_summary.result.read_latency_ms)
                }
              />
              <.split_dropdown_item
                selected_type={@selected_latency_type}
                value="write"
                event_name="select_latency_type"
                label={dgettext("dashboard_projects", "Write latency")}
                metric={
                  if @cache_summary.ok?, do: format_duration(@cache_summary.result.write_latency_ms)
                }
              />
            </:select>
          </.widget>
          <.widget
            id="once-cache-throughput"
            loading={!@cache_summary.ok?}
            title={throughput_title(@selected_throughput_type)}
            legend_color={split_legend_color(@selected_throughput_type, "flaky")}
            description={
              dgettext(
                "dashboard_projects",
                "Transferred remote-cache bytes divided by measured request time."
              )
            }
            value={
              if @cache_summary.ok?,
                do:
                  format_throughput(
                    throughput_value(@cache_summary.result, @selected_throughput_type)
                  )
            }
            trend_value={if @cache_summary.ok?, do: @cache_summary.result.throughput_trend}
            trend_type={:neutral}
            trend_label={@analytics_trend_label}
            empty={@cache_summary.ok? && @cache_summary.result.throughput_bytes_per_second == 0}
            phx_click="select_widget"
            phx_value_widget="cache_throughput"
            selected={@analytics_selected_widget == "cache_throughput"}
          >
            <:select>
              <.split_dropdown_item
                selected_type={@selected_throughput_type}
                value="combined"
                event_name="select_throughput_type"
                label={dgettext("dashboard_projects", "Cache throughput")}
                metric={
                  if @cache_summary.ok?,
                    do: format_throughput(@cache_summary.result.throughput_bytes_per_second)
                }
              />
              <.split_dropdown_item
                selected_type={@selected_throughput_type}
                value="downloads"
                event_name="select_throughput_type"
                label={dgettext("dashboard_projects", "Download throughput")}
                metric={
                  if @cache_summary.ok?,
                    do: format_throughput(@cache_summary.result.download_throughput_bytes_per_second)
                }
              />
              <.split_dropdown_item
                selected_type={@selected_throughput_type}
                value="uploads"
                event_name="select_throughput_type"
                label={dgettext("dashboard_projects", "Upload throughput")}
                metric={
                  if @cache_summary.ok?,
                    do: format_throughput(@cache_summary.result.upload_throughput_bytes_per_second)
                }
              />
            </:select>
          </.widget>
        </div>
        <.card_section :if={!@cache_analytics.ok?} data-part="analytics-card-chart-section">
          <.skeleton_chart />
        </.card_section>
        <.card_section
          :if={
            @cache_analytics.ok? &&
              analytics_has_data?(@cache_analytics.result, @analytics_selected_widget)
          }
          data-part="analytics-card-chart-section"
        >
          <.chart_type_toggle
            :if={@analytics_selected_widget == "cache_hit_rate"}
            id="once-cache-hit-rate"
            chart_type={@hit_rate_chart_type}
            chart_type_event="select_hit_rate_chart_type"
            group_by_options={[
              %{value: "host", label: dgettext("dashboard_projects", "Host")},
              %{value: "version", label: dgettext("dashboard_projects", "Once version")}
            ]}
            selected_group_by={@hit_rate_scatter_group_by}
            group_by_query_param="cache-hit-rate-scatter-group-by"
            uri={@uri}
          />
          <.scatter_chart
            :if={@analytics_selected_widget == "cache_hit_rate" and @hit_rate_chart_type == "scatter"}
            id="once-cache-hit-rate-scatter-chart"
            chart={@hit_rate_chart}
            period={@analytics_period}
            value_format="{value}%"
            y_axis_max={100}
            url_fn={
              fn point ->
                ~p"/#{@selected_account.name}/#{@selected_project.name}/once/runs/#{point.id}"
              end
            }
            truncation_title={
              dgettext(
                "dashboard_projects",
                "The 1,000 run limit has been reached, data is only included up to %{date}. Try narrowing the date range to see more recent runs.",
                date: scatter_oldest_entry_formatted(@hit_rate_chart.result)
              )
            }
          />
          <.chart
            :if={
              not (@analytics_selected_widget == "cache_hit_rate" and
                     @hit_rate_chart_type == "scatter")
            }
            id="once-cache-analytics-chart"
            type="line"
            extra_options={
              chart_options(
                @cache_analytics.result.dates,
                @analytics_selected_widget,
                @analytics_granularity
              )
            }
            series={chart_series(@cache_analytics.result, @analytics_selected_widget)}
            y_axis_min={0}
            y_axis_max={if @analytics_selected_widget == "cache_hit_rate", do: 100}
          />
        </.card_section>
        <.empty_card_section
          :if={
            @cache_analytics.ok? &&
              !analytics_has_data?(@cache_analytics.result, @analytics_selected_widget)
          }
          data-part="analytics-card-chart-section"
          title={cache_observations_empty_state_title(@has_any_cache_observations.result)}
        >
          <:image>
            <img
              src={~p"/images/empty_line_chart_light.png"}
              data-theme="light"
              loading="lazy"
              decoding="async"
            />
            <img
              src={~p"/images/empty_line_chart_dark.png"}
              data-theme="dark"
              loading="lazy"
              decoding="async"
            />
          </:image>
        </.empty_card_section>
      </.card>

      <.card
        title={dgettext("dashboard_projects", "Recent Runs")}
        icon="dashboard"
        data-part="bazel-cache-invocations-card"
      >
        <:actions>
          <.button
            variant="secondary"
            label={dgettext("dashboard_projects", "View more")}
            size="medium"
            navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/once/builds"}
            disabled={!@recent_cache_invocations.ok? || Enum.empty?(@recent_cache_invocations.result)}
          />
        </:actions>
        <.card_section
          :if={@recent_cache_invocations.ok? && Enum.any?(@recent_cache_invocations.result)}
          data-part="bazel-cache-invocations-section"
        >
          <div data-part="builds-section">
            <div data-part="builds-chart">
              <.legend
                title={dgettext("dashboard_projects", "Action cache hit rate")}
                value={"#{average_invocation_hit_rate(@recent_cache_invocations.result)}%"}
                style="primary"
              />
              <.chart
                id="once-cache-invocations-hit-rate-chart"
                type="bar"
                extra_options={
                  %{
                    grid: %{width: "98%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
                    tooltip: %{valueFormat: "{value}%", dateFormat: "minute"},
                    xAxis: %{
                      axisLabel: %{show: false},
                      data:
                        @recent_cache_invocations.result
                        |> Enum.reverse()
                        |> Enum.map(& &1.finished_at)
                    },
                    yAxis: %{
                      splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
                      axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}%"}
                    },
                    legend: %{show: false}
                  }
                }
                series={[
                  %{
                    data:
                      cache_invocation_chart_data(
                        @recent_cache_invocations.result,
                        @selected_account,
                        @selected_project
                      ),
                    name: dgettext("dashboard_projects", "Action cache hit rate"),
                    type: "bar",
                    barMinHeight: 3
                  }
                ]}
                y_axis_min={0}
                y_axis_max={100}
                grid_lines
                bar_width={8}
                bar_radius={2}
              />
            </div>
            <.table
              id="once-cache-invocations-table"
              rows={Enum.take(@recent_cache_invocations.result, 7)}
              row_key={fn invocation -> invocation.invocation_id end}
              row_navigate={
                fn invocation ->
                  url(
                    ~p"/#{@selected_account.name}/#{@selected_project.name}/once/runs/#{invocation.invocation_id}"
                  )
                end
              }
            >
              <:col :let={invocation} label={dgettext("dashboard_projects", "Run")}>
                <.text_and_description_cell label={invocation.command} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Hit rate")}>
                <.text_cell label={"#{invocation.cache.hit_rate}%"} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Downloaded")}>
                <.text_cell label={ByteFormatter.format_bytes(invocation.cache.download_bytes)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Uploaded")}>
                <.text_cell label={ByteFormatter.format_bytes(invocation.cache.upload_bytes)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Duration")}>
                <.text_cell
                  label={DateFormatter.format_duration_from_milliseconds(invocation.duration_ms)}
                  icon="history"
                />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Ran at")}>
                <.text_cell sublabel={DateFormatter.from_now(invocation.finished_at)} />
              </:col>
            </.table>
          </div>
        </.card_section>
        <.skeleton_chart :if={!@recent_cache_invocations.ok?} />
        <.empty_card_section
          :if={
            @recent_cache_invocations.ok? && @has_any_cache_observations.ok? &&
              Enum.empty?(@recent_cache_invocations.result)
          }
          title={cache_invocations_empty_state_title(@has_any_cache_observations.result)}
        >
          <:image>
            <img
              src={~p"/images/empty_table_light.png"}
              data-theme="light"
              loading="lazy"
              decoding="async"
            />
            <img
              src={~p"/images/empty_table_dark.png"}
              data-theme="dark"
              loading="lazy"
              decoding="async"
            />
          </:image>
        </.empty_card_section>
      </.card>
    </div>
    """
  end

  # ---- Data-shape helpers -----------------------------------------------

  defp cache_summary_with_trends(project_id, {start_datetime, end_datetime} = period) do
    summary = CacheAnalytics.summary(project_id, period_opts(period))
    previous_summary = CacheAnalytics.summary(project_id, period_opts(previous_period(start_datetime, end_datetime)))
    hit_rate_metrics = CacheAnalytics.invocation_hit_rate_metrics(project_id, period_opts(period))

    previous_hit_rate_metrics =
      CacheAnalytics.invocation_hit_rate_metrics(
        project_id,
        period_opts(previous_period(start_datetime, end_datetime))
      )

    Map.merge(summary, %{
      hit_rate_metrics: hit_rate_metrics,
      hit_rate_trends: %{
        avg: trend(previous_hit_rate_metrics.avg, hit_rate_metrics.avg),
        p99: trend(previous_hit_rate_metrics.p99, hit_rate_metrics.p99),
        p90: trend(previous_hit_rate_metrics.p90, hit_rate_metrics.p90),
        p50: trend(previous_hit_rate_metrics.p50, hit_rate_metrics.p50)
      },
      transfer_trend: trend(previous_summary.transfer_bytes, summary.transfer_bytes),
      latency_trend: trend(previous_summary.latency_ms, summary.latency_ms),
      throughput_trend: trend(previous_summary.throughput_bytes_per_second, summary.throughput_bytes_per_second)
    })
  end

  defp analytics_has_data?(analytics, "cache_hit_rate"), do: Enum.any?(analytics.lookup_values, &(&1 > 0))

  defp analytics_has_data?(analytics, widget) when widget in ["cache_transfer", "cache_latency", "cache_throughput"],
    do: Enum.any?(analytics.observation_values, &(&1 > 0))

  defp analytics_has_data?(_analytics, _widget), do: false

  # ---- Chart options + series (verbatim from BazelCacheLive) -----------

  defp chart_options(dates, "cache_hit_rate", granularity) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: chart_y_axis("{value}%"),
      tooltip: chart_tooltip("{value}%", granularity),
      legend: %{show: false}
    }
  end

  defp chart_options(dates, "cache_latency", granularity) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: chart_y_axis("fn:formatMilliseconds"),
      tooltip: chart_tooltip("fn:formatMilliseconds", granularity),
      legend: %{show: false}
    }
  end

  defp chart_options(dates, "cache_throughput", granularity) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: chart_y_axis("fn:formatMbps"),
      tooltip: chart_tooltip("fn:formatMbps", granularity),
      legend: %{show: false}
    }
  end

  defp chart_options(dates, _widget, granularity) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: chart_y_axis("fn:formatBytes"),
      tooltip: chart_tooltip("fn:formatBytes", granularity),
      legend: %{show: false}
    }
  end

  defp chart_series(analytics, "cache_hit_rate") do
    [
      chart_series(
        analytics.dates,
        analytics.hit_rate_values,
        "var:noora-chart-primary",
        dgettext("dashboard_projects", "Action cache hit rate")
      )
    ]
  end

  defp chart_series(analytics, "cache_transfer") do
    [
      chart_series(
        analytics.dates,
        analytics.download_bytes_values,
        "var:noora-chart-secondary",
        dgettext("dashboard_projects", "Downloaded")
      ),
      chart_series(
        analytics.dates,
        analytics.upload_bytes_values,
        "var:noora-chart-p99",
        dgettext("dashboard_projects", "Uploaded")
      )
    ]
  end

  defp chart_series(analytics, "cache_latency") do
    [
      chart_series(
        analytics.dates,
        analytics.latency_values,
        "var:noora-chart-p90",
        dgettext("dashboard_projects", "Cache latency")
      ),
      chart_series(
        analytics.dates,
        analytics.read_latency_values,
        "var:noora-chart-secondary",
        dgettext("dashboard_projects", "Read latency")
      ),
      chart_series(
        analytics.dates,
        analytics.write_latency_values,
        "var:noora-chart-p99",
        dgettext("dashboard_projects", "Write latency")
      )
    ]
  end

  defp chart_series(analytics, "cache_throughput") do
    [
      chart_series(
        analytics.dates,
        analytics.throughput_values,
        "var:noora-chart-flaky",
        dgettext("dashboard_projects", "Cache throughput")
      ),
      chart_series(
        analytics.dates,
        analytics.download_throughput_values,
        "var:noora-chart-secondary",
        dgettext("dashboard_projects", "Download throughput")
      ),
      chart_series(
        analytics.dates,
        analytics.upload_throughput_values,
        "var:noora-chart-p99",
        dgettext("dashboard_projects", "Upload throughput")
      )
    ]
  end

  defp chart_series(dates, values, color, name) do
    %{
      color: color,
      data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1),
      name: name,
      type: "line",
      smooth: 0.1,
      symbol: "none"
    }
  end

  defp replace_split_query_param(socket, key, value) do
    query = Query.put(socket.assigns.uri.query, key, value)

    push_patch(socket, to: cache_path(socket, query), replace: true)
  end

  defp cache_path(socket, query_string) when is_binary(query_string) do
    "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/once-cache?#{query_string}"
  end

  defp cache_path(socket, params) when is_map(params) do
    "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/once-cache?#{URI.encode_query(params)}"
  end

  # ---- Widget titles + selection helpers -------------------------------

  defp hit_rate_title("p99"), do: dgettext("dashboard_projects", "p99 action cache hit rate")
  defp hit_rate_title("p90"), do: dgettext("dashboard_projects", "p90 action cache hit rate")
  defp hit_rate_title("p50"), do: dgettext("dashboard_projects", "p50 action cache hit rate")
  defp hit_rate_title(_), do: dgettext("dashboard_projects", "Avg. cache hit rate")

  defp percentile_legend_color("p99"), do: "p99"
  defp percentile_legend_color("p90"), do: "p90"
  defp percentile_legend_color("p50"), do: "p50"
  defp percentile_legend_color(_), do: "primary"

  defp hit_rate_value(metrics, "p99"), do: "#{metrics.p99}%"
  defp hit_rate_value(metrics, "p90"), do: "#{metrics.p90}%"
  defp hit_rate_value(metrics, "p50"), do: "#{metrics.p50}%"
  defp hit_rate_value(metrics, _type), do: "#{metrics.avg}%"

  defp hit_rate_metric_values(metrics) do
    metrics
    |> Map.take([:avg, :p99, :p90, :p50])
    |> Map.new(fn {type, value} -> {type, "#{value}%"} end)
  end

  defp hit_rate_trend(trends, "p99"), do: trends.p99
  defp hit_rate_trend(trends, "p90"), do: trends.p90
  defp hit_rate_trend(trends, "p50"), do: trends.p50
  defp hit_rate_trend(trends, _type), do: trends.avg

  defp transfer_title("downloads"), do: dgettext("dashboard_projects", "Cache downloads")
  defp transfer_title("uploads"), do: dgettext("dashboard_projects", "Cache uploads")
  defp transfer_title(_), do: dgettext("dashboard_projects", "Cache transfer")

  defp latency_title("read"), do: dgettext("dashboard_projects", "Read latency")
  defp latency_title("write"), do: dgettext("dashboard_projects", "Write latency")
  defp latency_title(_), do: dgettext("dashboard_projects", "Cache latency")

  defp throughput_title("downloads"), do: dgettext("dashboard_projects", "Cache download throughput")

  defp throughput_title("uploads"), do: dgettext("dashboard_projects", "Cache upload throughput")
  defp throughput_title(_), do: dgettext("dashboard_projects", "Cache throughput")

  defp selected_hit_rate_type(type) when type in ["avg", "p99", "p90", "p50"], do: type
  defp selected_hit_rate_type(_), do: "avg"

  defp cache_observations_empty_state_title(true),
    do: dgettext("dashboard_projects", "No cache observations in the selected period")

  defp cache_observations_empty_state_title(_), do: dgettext("dashboard_projects", "No cache observations yet")

  defp cache_invocations_empty_state_title(true),
    do: dgettext("dashboard_projects", "No cache activity associated with a run in the selected period")

  defp cache_invocations_empty_state_title(_),
    do: dgettext("dashboard_projects", "No cache activity associated with a run yet")

  defp transfer_value(summary, "downloads"), do: summary.download_bytes
  defp transfer_value(summary, "uploads"), do: summary.upload_bytes
  defp transfer_value(summary, _combined), do: summary.transfer_bytes

  defp latency_value(summary, "read"), do: summary.read_latency_ms
  defp latency_value(summary, "write"), do: summary.write_latency_ms
  defp latency_value(summary, _combined), do: summary.latency_ms

  defp throughput_value(summary, "downloads"), do: summary.download_throughput_bytes_per_second
  defp throughput_value(summary, "uploads"), do: summary.upload_throughput_bytes_per_second
  defp throughput_value(summary, _combined), do: summary.throughput_bytes_per_second

  defp split_legend_color("downloads", _), do: "secondary"
  defp split_legend_color("uploads", _), do: "p99"
  defp split_legend_color("read", _), do: "secondary"
  defp split_legend_color("write", _), do: "p99"
  defp split_legend_color(_combined, combined_color), do: combined_color

  defp format_duration(duration), do: DateFormatter.format_duration_from_milliseconds(duration)
  defp format_throughput(value), do: ThroughputFormatter.format_throughput(value)

  defp cache_invocation_chart_data(invocations, account, project) do
    invocations
    |> Enum.reverse()
    |> Enum.map(fn invocation ->
      %{
        value: invocation.cache.hit_rate,
        date: invocation.finished_at,
        url: ~p"/#{account.name}/#{project.name}/once/runs/#{invocation.invocation_id}"
      }
    end)
  end

  defp average_invocation_hit_rate([]), do: 0.0

  defp average_invocation_hit_rate(invocations) do
    invocations
    |> Enum.map(& &1.cache.hit_rate)
    |> Enum.sum()
    |> Kernel./(length(invocations))
    |> Float.round(1)
  end

  attr(:selected_type, :string, required: true)
  attr(:value, :string, required: true)
  attr(:event_name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:metric, :string, default: nil)

  defp split_dropdown_item(assigns) do
    ~H"""
    <.dropdown_item
      value={@value}
      phx-click={@event_name}
      phx-value-type={@value}
      data-selected={@selected_type == @value}
    >
      <div data-part="percentile-item">
        <div data-part="dot" data-type={@value}></div>
        <span data-part="label">{@label}</span>
        <span data-part="separator">-</span>
        <span data-part="value">{@metric || dgettext("dashboard", "N/A")}</span>
      </div>
    </.dropdown_item>
    """
  end

  # Only the hit rate widget has a scatter view; the other three are
  # aggregates over the period with no per-run point to plot.
  defp hit_rate_chart_type("scatter"), do: "scatter"
  defp hit_rate_chart_type(_line), do: "line"

  defp scatter_group_by("version"), do: "version"
  defp scatter_group_by(_host), do: "host"

  defp assign_hit_rate_scatter(socket, "scatter", group_by, period) do
    project_id = socket.assigns.selected_project.id
    opts = period |> period_opts() |> Keyword.put(:group_by, String.to_existing_atom(group_by))

    assign_async(socket, :hit_rate_chart, fn ->
      {:ok, %{hit_rate_chart: {:scatter, CacheAnalytics.hit_rate_scatter_data(project_id, opts)}}}
    end)
  end

  defp assign_hit_rate_scatter(socket, _line, _group_by, _period) do
    assign(socket, :hit_rate_chart, AsyncResult.ok(:line))
  end
end
