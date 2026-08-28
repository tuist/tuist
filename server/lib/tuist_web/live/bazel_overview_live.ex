defmodule TuistWeb.BazelOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton

  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker

  def assign_mount(socket), do: socket

  def assign_handle_params(socket, params, uri_path) do
    project = socket.assigns.selected_project
    uri = URI.new!("?" <> URI.encode_query(params))

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    %{preset: invocations_preset, period: invocations_period} =
      DatePicker.date_picker_params(params, "builds")

    analytics_opts = period_opts(analytics_period)
    invocations_opts = period_opts(invocations_period)

    socket
    |> assign(
      uri: uri,
      uri_path: uri_path,
      analytics_preset: analytics_preset,
      analytics_period: analytics_period,
      analytics_trend_label: analytics_trend_label(analytics_preset),
      invocations_preset: invocations_preset,
      invocations_period: invocations_period
    )
    |> assign_async(:reapi_cache_summary, fn ->
      {:ok, %{reapi_cache_summary: cache_summary_with_trends(project.id, analytics_period)}}
    end)
    |> assign_async(:cache_hit_rate_analytics, fn ->
      {:ok, %{cache_hit_rate_analytics: ReapiCache.hit_rate_analytics(project.id, analytics_opts)}}
    end)
    |> assign_async(:recent_invocations, fn ->
      {:ok, %{recent_invocations: recent_invocation_chart_data(Bazel.recent_invocations(project.id), project)}}
    end)
    |> assign_async(:invocation_duration_analytics, fn ->
      {:ok, %{invocation_duration_analytics: Bazel.duration_analytics(project.id, invocations_opts)}}
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="bazel-overview">
      <.card
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="analytics-card"
      >
        <:actions>
          <.date_picker
            id="bazel-analytics-date-range-picker"
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
                    detail: %{id: "bazel-analytics-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply",
                    detail: %{id: "bazel-analytics-date-range-picker"}
                  )
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="widgets">
          <.widget
            id="bazel-action-cache-hit-rate"
            loading={!@reapi_cache_summary.ok?}
            title={dgettext("dashboard_projects", "Action cache hit rate")}
            description={
              dgettext(
                "dashboard_projects",
                "The share of action-cache lookups that Kura served from the remote cache."
              )
            }
            value={
              if @reapi_cache_summary.ok? and @reapi_cache_summary.result.hit_rate,
                do: "#{@reapi_cache_summary.result.hit_rate}%"
            }
            trend_value={if @reapi_cache_summary.ok?, do: @reapi_cache_summary.result.hit_rate_trend}
            trend_label={@analytics_trend_label}
            empty={@reapi_cache_summary.ok? && is_nil(@reapi_cache_summary.result.hit_rate)}
          />
          <.widget
            id="bazel-action-cache-lookups"
            loading={!@reapi_cache_summary.ok?}
            title={dgettext("dashboard_projects", "Action cache lookups")}
            description={
              dgettext("dashboard_projects", "Remote action-cache hits and misses observed by Kura.")
            }
            value={
              if @reapi_cache_summary.ok?,
                do: "#{@reapi_cache_summary.result.hits + @reapi_cache_summary.result.misses}"
            }
            trend_value={if @reapi_cache_summary.ok?, do: @reapi_cache_summary.result.lookups_trend}
            trend_label={@analytics_trend_label}
            empty={
              @reapi_cache_summary.ok? &&
                @reapi_cache_summary.result.hits + @reapi_cache_summary.result.misses == 0
            }
          />
          <.widget
            id="bazel-cache-downloads"
            loading={!@reapi_cache_summary.ok?}
            title={dgettext("dashboard_projects", "Downloaded")}
            description={
              dgettext(
                "dashboard_projects",
                "Bytes Kura served while returning action-cache results."
              )
            }
            value={
              if @reapi_cache_summary.ok?,
                do: ByteFormatter.format_bytes(@reapi_cache_summary.result.download_bytes)
            }
            trend_value={
              if @reapi_cache_summary.ok?, do: @reapi_cache_summary.result.download_bytes_trend
            }
            trend_label={@analytics_trend_label}
            empty={@reapi_cache_summary.ok? && @reapi_cache_summary.result.download_bytes == 0}
          />
          <.widget
            id="bazel-cache-uploads"
            loading={!@reapi_cache_summary.ok?}
            title={dgettext("dashboard_projects", "Uploaded")}
            description={
              dgettext(
                "dashboard_projects",
                "Bytes Kura accepted while storing action-cache results."
              )
            }
            value={
              if @reapi_cache_summary.ok?,
                do: ByteFormatter.format_bytes(@reapi_cache_summary.result.upload_bytes)
            }
            trend_value={
              if @reapi_cache_summary.ok?, do: @reapi_cache_summary.result.upload_bytes_trend
            }
            trend_label={@analytics_trend_label}
            empty={@reapi_cache_summary.ok? && @reapi_cache_summary.result.upload_bytes == 0}
          />
        </div>
        <.card_section :if={!@cache_hit_rate_analytics.ok?} data-part="cache-hit-rate-chart-section">
          <div data-part="cache-hit-rate-chart">
            <.skeleton_legend />
            <.skeleton_chart />
          </div>
        </.card_section>
        <.card_section
          :if={
            @cache_hit_rate_analytics.ok? &&
              Enum.any?(@cache_hit_rate_analytics.result.values, &(&1 != 0))
          }
          data-part="cache-hit-rate-chart-section"
        >
          <div data-part="cache-hit-rate-chart">
            <.legend
              title={dgettext("dashboard_projects", "Action cache hit rate")}
              value={
                if @cache_hit_rate_analytics.result.hit_rate,
                  do: "#{@cache_hit_rate_analytics.result.hit_rate}%"
              }
              style="primary"
            />
            <.chart
              id="bazel-cache-hit-rate-chart"
              type="line"
              extra_options={cache_hit_rate_chart_options(@cache_hit_rate_analytics.result.dates)}
              series={[
                %{
                  color: "var:noora-chart-primary",
                  data:
                    Enum.zip(
                      @cache_hit_rate_analytics.result.dates,
                      @cache_hit_rate_analytics.result.values
                    )
                    |> Enum.map(&Tuple.to_list/1),
                  name: dgettext("dashboard_projects", "Action cache hit rate"),
                  type: "line",
                  smooth: 0.1,
                  symbol: "none"
                }
              ]}
              y_axis_min={0}
              y_axis_max={100}
            />
          </div>
        </.card_section>
        <.empty_card_section
          :if={
            @cache_hit_rate_analytics.ok? &&
              Enum.all?(@cache_hit_rate_analytics.result.values, &(&1 == 0))
          }
          title={dgettext("dashboard_projects", "No cache observations yet")}
          get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
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
        title={dgettext("dashboard_projects", "Invocations")}
        icon="subtask"
        data-part="invocations-card"
      >
        <:actions>
          <.date_picker
            id="bazel-invocations-date-range-picker"
            name="builds-date-range"
            presets={date_picker_presets()}
            selected_preset={@invocations_preset}
            period={@invocations_period}
            on_period_change="builds_period_changed"
            max={Date.utc_today()}
          >
            <:actions>
              <.button
                label={dgettext("dashboard_projects", "Cancel")}
                variant="secondary"
                phx-click={
                  JS.dispatch("phx:date-picker-cancel",
                    detail: %{id: "bazel-invocations-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply",
                    detail: %{id: "bazel-invocations-date-range-picker"}
                  )
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="invocation-card-sections">
          <.card_section :if={!@recent_invocations.ok?}>
            <div data-part="recent-invocations-chart">
              <div data-part="legends"><.skeleton_legend /><.skeleton_legend /></div>
              <.skeleton_chart />
            </div>
          </.card_section>
          <.card_section :if={@recent_invocations.ok? && Enum.any?(@recent_invocations.result)}>
            <div data-part="recent-invocations-chart">
              <div data-part="legends">
                <.legend
                  title={dgettext("dashboard_projects", "Passed invocations")}
                  value={Enum.count(@recent_invocations.result, &(&1.status == "success"))}
                  style="primary"
                />
                <.legend
                  title={dgettext("dashboard_projects", "Failed invocations")}
                  value={Enum.count(@recent_invocations.result, &(&1.status == "failure"))}
                  style="destructive"
                />
              </div>
              <.chart
                id="bazel-recent-invocations-chart"
                type="bar"
                extra_options={recent_invocations_chart_options(@recent_invocations.result)}
                series={[%{data: @recent_invocations.result, name: "Invocation", type: "bar"}]}
                y_axis_min={0}
                grid_lines
                bar_width={8}
                bar_radius={2}
              />
              <span data-part="label">{dgettext("dashboard_projects", "Last 30 invocations")}</span>
            </div>
          </.card_section>
          <.empty_card_section
            :if={@recent_invocations.ok? && Enum.empty?(@recent_invocations.result)}
            title={dgettext("dashboard_projects", "No invocations yet")}
            get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
          >
            <:image>
              <img
                src={~p"/images/empty_bar_chart_light.png"}
                data-theme="light"
                loading="lazy"
                decoding="async"
              />
              <img
                src={~p"/images/empty_bar_chart_dark.png"}
                data-theme="dark"
                loading="lazy"
                decoding="async"
              />
            </:image>
          </.empty_card_section>
          <.card_section
            :if={!@invocation_duration_analytics.ok?}
            data-part="average-invocation-duration-card-section"
          >
            <div data-part="average-invocation-duration-chart">
              <.skeleton_legend /><.skeleton_chart />
            </div>
          </.card_section>
          <.card_section
            :if={
              @invocation_duration_analytics.ok? &&
                @invocation_duration_analytics.result.total_average_duration != 0
            }
            data-part="average-invocation-duration-card-section"
          >
            <div data-part="average-invocation-duration-chart">
              <.button
                data-part="view-more"
                label={dgettext("dashboard_projects", "View more")}
                size="small"
                variant="secondary"
                navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/invocations"}
              />
              <.legend
                title={dgettext("dashboard_projects", "Average invocation duration")}
                value={
                  DateFormatter.format_duration_from_milliseconds(
                    @invocation_duration_analytics.result.total_average_duration
                  )
                }
                style="secondary"
              />
              <.chart
                id="bazel-average-invocation-duration-chart"
                type="line"
                extra_options={duration_chart_options(@invocation_duration_analytics.result.dates)}
                series={[
                  %{
                    color: "var:noora-chart-secondary",
                    data:
                      Enum.zip(
                        @invocation_duration_analytics.result.dates,
                        @invocation_duration_analytics.result.values
                      )
                      |> Enum.map(&Tuple.to_list/1),
                    name: dgettext("dashboard_projects", "Average invocation duration"),
                    type: "line",
                    smooth: 0.1,
                    symbol: "none"
                  }
                ]}
                y_axis_min={0}
              />
            </div>
          </.card_section>
          <.empty_card_section
            :if={
              @invocation_duration_analytics.ok? &&
                @invocation_duration_analytics.result.total_average_duration == 0
            }
            title={dgettext("dashboard_projects", "No invocations yet")}
            get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
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
        </div>
      </.card>
    </div>
    """
  end

  defp recent_invocation_chart_data(invocations, project) do
    invocations
    |> Enum.reverse()
    |> Enum.map(fn invocation ->
      %{
        value: invocation.duration_ms,
        itemStyle: %{
          color:
            if(invocation.status == "success",
              do: "var:noora-chart-primary",
              else: "var:noora-chart-destructive"
            )
        },
        date: invocation.finished_at,
        url: ~p"/#{project.account.name}/#{project.name}/invocations/#{invocation.invocation_id}",
        status: invocation.status
      }
    end)
  end

  defp period_opts({start_datetime, end_datetime}), do: [start_datetime: start_datetime, end_datetime: end_datetime]

  defp cache_summary_with_trends(project_id, {start_datetime, end_datetime} = period) do
    summary = ReapiCache.summary(project_id, period_opts(period))
    previous_summary = ReapiCache.summary(project_id, period_opts(previous_period(start_datetime, end_datetime)))

    Map.merge(summary, %{
      hit_rate_trend: trend(previous_summary.hit_rate, summary.hit_rate),
      lookups_trend: trend(lookups(previous_summary), lookups(summary)),
      download_bytes_trend: trend(previous_summary.download_bytes, summary.download_bytes),
      upload_bytes_trend: trend(previous_summary.upload_bytes, summary.upload_bytes)
    })
  end

  defp previous_period(start_datetime, end_datetime) do
    duration = DateTime.diff(end_datetime, start_datetime, :second)
    {DateTime.add(start_datetime, -duration, :second), start_datetime}
  end

  defp lookups(summary), do: summary.hits + summary.misses

  defp trend(previous_value, current_value) do
    previous_value = numeric(previous_value)
    current_value = numeric(current_value)

    if previous_value == 0 or current_value == 0 do
      0.0
    else
      Float.round((current_value - previous_value) / previous_value * 100, 1)
    end
  end

  defp numeric(nil), do: 0
  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_projects", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_projects", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_projects", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_projects", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_projects", "since last month")

  defp date_picker_presets do
    [
      %{id: "last-24-hours", label: dgettext("dashboard_projects", "Last 24 hours"), period: {24, :hour}},
      %{id: "last-7-days", label: dgettext("dashboard_projects", "Last 7 days"), period: {7, :day}},
      %{id: "last-30-days", label: dgettext("dashboard_projects", "Last 30 days"), period: {30, :day}},
      %{id: "last-12-months", label: dgettext("dashboard_projects", "Last 12 months"), period: {12, :month}},
      %{id: "custom", label: dgettext("dashboard_projects", "Custom")}
    ]
  end

  defp cache_hit_rate_chart_options(dates) do
    %{
      grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
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
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}%"}
      },
      tooltip: %{valueFormat: "{value}%"},
      legend: %{show: false}
    }
  end

  defp recent_invocations_chart_options(invocations) do
    %{
      grid: %{width: "100%", left: "0.4%", height: "88%", top: "5%"},
      tooltip: %{valueFormat: "fn:formatMilliseconds", dateFormat: "minute"},
      xAxis: %{axisLabel: %{show: false}, data: Enum.map(invocations, & &1.date)},
      yAxis: %{
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatMilliseconds"}
      },
      legend: %{show: false}
    }
  end

  defp duration_chart_options(dates) do
    %{
      grid: %{width: "95%", left: "0.4%", height: "88%", top: "5%"},
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
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatMilliseconds"}
      },
      tooltip: %{valueFormat: "fn:formatMilliseconds"},
      legend: %{show: false}
    }
  end
end
