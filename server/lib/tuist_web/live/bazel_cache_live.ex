defmodule TuistWeb.BazelCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard", "Cache")} · #{account.name}/#{project.name} · Tuist")
     |> assign(OpenGraph.og_image_assigns("overview"))
     |> assign(:available_filters, define_filters())}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project}} = socket) do
    params = Query.query_params(uri)

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    sort_by = params["cache-sort-by"] || "observed"
    sort_order = params["cache-sort-order"] || "desc"
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    filters =
      [%{field: :project_id, op: :==, value: project.id}] ++
        Filter.Operations.convert_filters_to_flop(active_filters)

    {cache_events, meta} =
      ReapiCache.list_cache_events(project.id, %{
        filters: filters,
        order_by: [sort_field(sort_by)],
        order_directions: [sort_direction(sort_order)],
        page: parse_page(params["page"]),
        page_size: @page_size
      })

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:analytics_preset, analytics_preset)
     |> assign(:analytics_period, analytics_period)
     |> assign(:analytics_trend_label, analytics_trend_label(analytics_preset))
     |> assign(:analytics_selected_widget, params["analytics-selected-widget"] || "cache_hit_rate")
     |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
     |> assign(:selected_transfer_type, params["transfer-type"] || "combined")
     |> assign(:selected_latency_type, params["latency-type"] || "combined")
     |> assign(:selected_throughput_type, params["throughput-type"] || "combined")
     |> assign(:cache_events, cache_events)
     |> assign(:current_page, meta.current_page)
     |> assign(:total_pages, meta.total_pages)
     |> assign(:cache_sort_by, sort_by)
     |> assign(:cache_sort_order, sort_order)
     |> assign(:active_filters, active_filters)
     |> assign_async([:cache_summary, :cache_analytics], fn ->
       {:ok,
        %{
          cache_summary: cache_summary_with_trends(project.id, analytics_period),
          cache_analytics: ReapiCache.analytics(project.id, period_opts(analytics_period))
        }}
     end)
     |> assign_async(:recent_cache_invocations, fn ->
       {:ok,
        %{
          recent_cache_invocations:
            project.id
            |> Bazel.recent_invocations(Keyword.put(period_opts(analytics_period), :limit, 40))
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

  def handle_event("select_hit_rate_type", %{"type" => type}, socket) do
    {:noreply, replace_split_query_param(socket, "hit-rate-type", type)}
  end

  def handle_event("select_transfer_type", %{"type" => type}, socket) do
    {:noreply, replace_split_query_param(socket, "transfer-type", type)}
  end

  def handle_event("select_latency_type", %{"type" => type}, socket) do
    {:noreply, replace_split_query_param(socket, "latency-type", type)}
  end

  def handle_event("select_throughput_type", %{"type" => type}, socket) do
    {:noreply, replace_split_query_param(socket, "throughput-type", type)}
  end

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

    {:noreply,
     push_patch(
       socket,
       to: "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/bazel-cache?#{query_params}"
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: cache_path(socket, updated_params))
    |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
    |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})
    |> then(&{:noreply, &1})
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: cache_path(socket, updated_params))
    |> push_event("close-dropdown", %{id: "all", all: true})
    |> push_event("close-popover", %{id: "all", all: true})
    |> then(&{:noreply, &1})
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
            id="bazel-cache-date-range-picker"
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
                    detail: %{id: "bazel-cache-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply", detail: %{id: "bazel-cache-date-range-picker"})
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="widgets">
          <.percentile_dropdown_widget
            id="bazel-cache-hit-rate"
            loading={!@cache_summary.ok?}
            title={hit_rate_title(@selected_hit_rate_type)}
            legend_color={percentile_legend_color(@selected_hit_rate_type)}
            description={
              dgettext(
                "dashboard_projects",
                "The percentage of action-cache lookups that Kura served from the remote cache, measured per invocation."
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
            trend_value={if @cache_summary.ok?, do: @cache_summary.result.hit_rate_trend}
            trend_label={@analytics_trend_label}
            empty={@cache_summary.ok? && @cache_summary.result.hit_rate_metrics.avg == 0}
            phx_click="select_widget"
            phx_value_widget="cache_hit_rate"
            selected={@analytics_selected_widget == "cache_hit_rate"}
          />
          <.widget
            id="bazel-cache-transfer"
            loading={!@cache_summary.ok?}
            title={transfer_title(@selected_transfer_type)}
            legend_color={split_legend_color(@selected_transfer_type, "p50")}
            description={
              dgettext(
                "dashboard_projects",
                "The bytes Kura returned from and accepted for action-cache requests during the selected period."
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
                label={dgettext("dashboard_projects", "Action cache transfer")}
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
            id="bazel-cache-latency"
            loading={!@cache_summary.ok?}
            title={latency_title(@selected_latency_type)}
            legend_color={split_legend_color(@selected_latency_type, "p90")}
            description={
              dgettext(
                "dashboard_projects",
                "The average time Kura spent serving action-cache reads and writes during the selected period."
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
                label={dgettext("dashboard_projects", "Action cache latency")}
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
            id="bazel-cache-throughput"
            loading={!@cache_summary.ok?}
            title={throughput_title(@selected_throughput_type)}
            legend_color={split_legend_color(@selected_throughput_type, "flaky")}
            description={
              dgettext(
                "dashboard_projects",
                "Transferred action-cache bytes divided by Kura's measured request time. Requests without a measured duration are excluded."
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
                label={dgettext("dashboard_projects", "Action cache throughput")}
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
          <.chart
            id="bazel-cache-analytics-chart"
            type="line"
            extra_options={
              chart_options(
                @cache_analytics.result.dates,
                @analytics_selected_widget,
                @analytics_preset
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
        title={dgettext("dashboard_projects", "Invocations using cache")}
        icon="dashboard"
        data-part="bazel-cache-invocations-card"
      >
        <:actions>
          <.button
            variant="secondary"
            label={dgettext("dashboard_projects", "View more")}
            size="medium"
            navigate={~p"/#{@selected_project.account.name}/#{@selected_project.name}/invocations"}
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
                id="bazel-cache-invocations-hit-rate-chart"
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
                      cache_invocation_chart_data(@recent_cache_invocations.result, @selected_project),
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
              id="bazel-cache-invocations-table"
              rows={Enum.take(@recent_cache_invocations.result, 7)}
              row_navigate={
                fn invocation ->
                  url(
                    ~p"/#{@selected_project.account.name}/#{@selected_project.name}/invocations/#{invocation.invocation_id}"
                  )
                end
              }
            >
              <:col :let={invocation} label={dgettext("dashboard_projects", "Targets")}>
                <.text_cell label={target_patterns_label(invocation.target_patterns)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Command")}>
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
              <:col :let={invocation} label={dgettext("dashboard_projects", "Finished")}>
                <.text_cell sublabel={DateFormatter.from_now(invocation.finished_at)} />
              </:col>
            </.table>
          </div>
        </.card_section>
        <.skeleton_chart :if={!@recent_cache_invocations.ok?} />
        <.empty_card_section
          :if={@recent_cache_invocations.ok? && Enum.empty?(@recent_cache_invocations.result)}
          title={
            dgettext("dashboard_projects", "No cache activity associated with an invocation yet")
          }
          get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
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

      <.card
        title={dgettext("dashboard_projects", "Action cache activity")}
        icon="server"
        data-part="bazel-cache-activity-card"
      >
        <.card_section data-part="bazel-cache-events-section">
          <div data-part="filters">
            <.filter_dropdown
              id="bazel-cache-filter-dropdown"
              label={dgettext("dashboard_projects", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
          </div>
          <div :if={Enum.any?(@active_filters)} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <.table :if={Enum.any?(@cache_events)} id="bazel-cache-events-table" rows={@cache_events}>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Target")}
              patch={column_patch_sort(assigns, "target")}
              sort_order={@cache_sort_by == "target" && @cache_sort_order}
            >
              <.text_cell label={event.target_label} />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Outcome")}
              patch={column_patch_sort(assigns, "outcome")}
              sort_order={@cache_sort_by == "outcome" && @cache_sort_order}
            >
              <.status_badge_cell
                label={outcome_label(event.outcome)}
                status={outcome_status(event.outcome)}
              />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Action")}
              patch={column_patch_sort(assigns, "action")}
              sort_order={@cache_sort_by == "action" && @cache_sort_order}
            >
              <.text_cell label={event.action_mnemonic} />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Transfer")}
              patch={column_patch_sort(assigns, "transfer")}
              sort_order={@cache_sort_by == "transfer" && @cache_sort_order}
            >
              <.text_cell label={ByteFormatter.format_bytes(event.size)} />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Latency")}
              patch={column_patch_sort(assigns, "latency")}
              sort_order={@cache_sort_by == "latency" && @cache_sort_order}
            >
              <.text_cell
                label={DateFormatter.format_duration_from_milliseconds(event.duration_ms)}
                icon="history"
              />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Observed")}
              patch={column_patch_sort(assigns, "observed")}
              sort_order={@cache_sort_by == "observed" && @cache_sort_order}
            >
              <.text_cell sublabel={DateFormatter.from_now(event.inserted_at)} />
            </:col>
          </.table>
          <.pagination_group
            :if={@total_pages > 1}
            current_page={@current_page}
            number_of_pages={@total_pages}
            page_patch={fn page -> "?#{Query.put(@uri.query, "page", to_string(page))}" end}
          />
          <.empty_card_section
            :if={Enum.empty?(@cache_events)}
            title={dgettext("dashboard_projects", "No cache observations yet")}
            get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
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
        </.card_section>
      </.card>
    </div>
    """
  end

  defp cache_summary_with_trends(project_id, {start_datetime, end_datetime} = period) do
    summary = ReapiCache.summary(project_id, period_opts(period))
    previous_summary = ReapiCache.summary(project_id, period_opts(previous_period(start_datetime, end_datetime)))
    hit_rate_metrics = ReapiCache.invocation_hit_rate_metrics(project_id, period_opts(period))

    previous_hit_rate_metrics =
      ReapiCache.invocation_hit_rate_metrics(project_id, period_opts(previous_period(start_datetime, end_datetime)))

    Map.merge(summary, %{
      hit_rate_metrics: hit_rate_metrics,
      hit_rate_trend: trend(previous_hit_rate_metrics.avg, hit_rate_metrics.avg),
      transfer_trend: trend(previous_summary.transfer_bytes, summary.transfer_bytes),
      latency_trend: trend(previous_summary.latency_ms, summary.latency_ms),
      throughput_trend: trend(previous_summary.throughput_bytes_per_second, summary.throughput_bytes_per_second)
    })
  end

  defp analytics_has_data?(analytics, "cache_hit_rate"), do: Enum.any?(analytics.hit_rate_values, &(&1 != 0))

  defp analytics_has_data?(analytics, "cache_transfer") do
    Enum.any?(analytics.download_bytes_values, &(&1 != 0)) ||
      Enum.any?(analytics.upload_bytes_values, &(&1 != 0))
  end

  defp analytics_has_data?(analytics, "cache_latency") do
    Enum.any?(analytics.latency_values, &(&1 != 0))
  end

  defp analytics_has_data?(analytics, "cache_throughput") do
    Enum.any?(analytics.download_throughput_values, &(&1 != 0)) ||
      Enum.any?(analytics.upload_throughput_values, &(&1 != 0))
  end

  defp analytics_has_data?(_analytics, _widget), do: false

  defp chart_options(dates, "cache_hit_rate", preset) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("{value}%"),
      tooltip: chart_tooltip("{value}%", preset),
      legend: %{show: false}
    }
  end

  defp chart_options(dates, "cache_latency", preset) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("fn:formatMilliseconds"),
      tooltip: chart_tooltip("fn:formatMilliseconds", preset),
      legend: %{show: false}
    }
  end

  defp chart_options(dates, "cache_throughput", preset) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("fn:formatMbps"),
      tooltip: chart_tooltip("fn:formatMbps", preset),
      legend: %{show: false}
    }
  end

  defp chart_options(dates, _widget, preset) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("fn:formatBytes"),
      tooltip: chart_tooltip("fn:formatBytes", preset),
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
    combined_values =
      analytics.download_throughput_values
      |> Enum.zip(analytics.upload_throughput_values)
      |> Enum.map(fn {download, upload} -> download + upload end)

    [
      chart_series(
        analytics.dates,
        combined_values,
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

  defp chart_x_axis(dates) do
    %{
      boundaryGap: false,
      type: "category",
      axisLabel: %{
        color: "var:noora-surface-label-secondary",
        formatter: "fn:toLocaleDate",
        customValues: [List.first(dates), List.last(dates)],
        padding: [10, 0, 0, 0]
      }
    }
  end

  defp chart_y_axis(formatter),
    do: %{
      splitNumber: 4,
      splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
      axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
    }

  defp chart_tooltip(value_format, "last-24-hours"), do: %{valueFormat: value_format, dateFormat: "hour"}
  defp chart_tooltip(value_format, _preset), do: %{valueFormat: value_format}
  defp outcome_label("hit"), do: dgettext("dashboard_projects", "Hit")
  defp outcome_label("miss"), do: dgettext("dashboard_projects", "Miss")
  defp outcome_label(_), do: dgettext("dashboard_projects", "Stored")
  defp outcome_status("hit"), do: "success"
  defp outcome_status("miss"), do: "attention"
  defp outcome_status(_), do: "success"
  defp period_opts({start_datetime, end_datetime}), do: [start_datetime: start_datetime, end_datetime: end_datetime]

  defp replace_split_query_param(socket, key, value) do
    query = Query.put(socket.assigns.uri.query, key, value)

    push_patch(
      socket,
      to: "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/bazel-cache?#{query}",
      replace: true
    )
  end

  defp hit_rate_title("p99"), do: dgettext("dashboard_projects", "p99 action cache hit rate")
  defp hit_rate_title("p90"), do: dgettext("dashboard_projects", "p90 action cache hit rate")
  defp hit_rate_title("p50"), do: dgettext("dashboard_projects", "p50 action cache hit rate")
  defp hit_rate_title(_), do: dgettext("dashboard_projects", "Avg. action cache hit rate")
  defp percentile_legend_color("p99"), do: "p99"
  defp percentile_legend_color("p90"), do: "p90"
  defp percentile_legend_color("p50"), do: "p50"
  defp percentile_legend_color(_), do: "primary"

  defp hit_rate_value(metrics, type), do: "#{Map.get(metrics, String.to_atom(type), 0)}%"

  defp hit_rate_metric_values(metrics) do
    Map.new(metrics, fn {type, value} -> {type, "#{value}%"} end)
  end

  defp transfer_title("downloads"), do: dgettext("dashboard_projects", "Action cache downloads")
  defp transfer_title("uploads"), do: dgettext("dashboard_projects", "Action cache uploads")
  defp transfer_title(_), do: dgettext("dashboard_projects", "Action cache transfer")
  defp latency_title("read"), do: dgettext("dashboard_projects", "Read latency")
  defp latency_title("write"), do: dgettext("dashboard_projects", "Write latency")
  defp latency_title(_), do: dgettext("dashboard_projects", "Action cache latency")
  defp throughput_title("downloads"), do: dgettext("dashboard_projects", "Action cache download throughput")
  defp throughput_title("uploads"), do: dgettext("dashboard_projects", "Action cache upload throughput")
  defp throughput_title(_), do: dgettext("dashboard_projects", "Action cache throughput")

  defp transfer_value(summary, "downloads"), do: summary.download_bytes
  defp transfer_value(summary, "uploads"), do: summary.upload_bytes
  defp transfer_value(summary, _combined), do: summary.transfer_bytes
  defp latency_value(summary, "read"), do: summary.read_latency_ms
  defp latency_value(summary, "write"), do: summary.write_latency_ms
  defp latency_value(summary, _combined), do: summary.latency_ms

  defp throughput_value(summary, "downloads"), do: summary.download_throughput_bytes_per_second
  defp throughput_value(summary, "uploads"), do: summary.upload_throughput_bytes_per_second
  defp throughput_value(summary, _combined), do: summary.throughput_bytes_per_second

  defp split_legend_color("downloads", _combined_color), do: "secondary"
  defp split_legend_color("uploads", _combined_color), do: "p99"
  defp split_legend_color("read", _combined_color), do: "secondary"
  defp split_legend_color("write", _combined_color), do: "p99"
  defp split_legend_color(_combined, combined_color), do: combined_color
  defp format_duration(duration), do: DateFormatter.format_duration_from_milliseconds(duration)
  defp format_throughput(value), do: ThroughputFormatter.format_throughput(value)

  defp cache_invocation_chart_data(invocations, project) do
    invocations
    |> Enum.reverse()
    |> Enum.map(fn invocation ->
      %{
        value: invocation.cache.hit_rate,
        date: invocation.finished_at,
        url: ~p"/#{project.account.name}/#{project.name}/invocations/#{invocation.invocation_id}"
      }
    end)
  end

  defp average_invocation_hit_rate(invocations) do
    invocations
    |> Enum.map(& &1.cache.hit_rate)
    |> Enum.sum()
    |> Kernel./(length(invocations))
    |> Float.round(1)
  end

  defp target_patterns_label([]), do: dgettext("dashboard_projects", "No targets reported")

  defp target_patterns_label([first_target | remaining_targets]) do
    case length(remaining_targets) do
      0 -> first_target
      count -> "#{first_target} +#{count}"
    end
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

  defp previous_period(start_datetime, end_datetime),
    do: {DateTime.add(start_datetime, -DateTime.diff(end_datetime, start_datetime, :second), :second), start_datetime}

  defp trend(previous_value, current_value) do
    previous_value = numeric(previous_value)
    current_value = numeric(current_value)

    if previous_value == 0 or current_value == 0,
      do: 0.0,
      else: Float.round((current_value - previous_value) / previous_value * 100, 1)
  end

  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(nil), do: 0

  defp sort_field("outcome"), do: :outcome
  defp sort_field("action"), do: :action_mnemonic
  defp sort_field("target"), do: :target_label
  defp sort_field("transfer"), do: :size
  defp sort_field("latency"), do: :duration_ms
  defp sort_field(_), do: :inserted_at
  defp sort_direction("asc"), do: :asc
  defp sort_direction(_), do: :desc

  defp parse_page(value) do
    case Integer.parse(value || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp column_patch_sort(%{uri: uri, cache_sort_by: sort_by, cache_sort_order: sort_order}, column_value) do
    next_order = if sort_by == column_value and sort_order == "asc", do: "desc", else: "asc"

    uri.query
    |> URI.decode_query()
    |> Map.put("cache-sort-by", column_value)
    |> Map.put("cache-sort-order", next_order)
    |> Map.put("page", "1")
    |> URI.encode_query()
    |> then(&"?#{&1}")
  end

  defp cache_path(socket, params) do
    "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/bazel-cache?#{URI.encode_query(params)}"
  end

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

  defp define_filters do
    [
      %Filter.Filter{
        id: "outcome",
        field: :outcome,
        display_name: dgettext("dashboard_projects", "Outcome"),
        type: :option,
        options: ["hit", "miss", "write"],
        options_display_names: %{
          "hit" => dgettext("dashboard_projects", "Hit"),
          "miss" => dgettext("dashboard_projects", "Miss"),
          "write" => dgettext("dashboard_projects", "Stored")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "action",
        field: :action_mnemonic,
        display_name: dgettext("dashboard_projects", "Action"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "target",
        field: :target_label,
        display_name: dgettext("dashboard_projects", "Target"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "invocation",
        field: :invocation_id,
        display_name: dgettext("dashboard_projects", "Invocation"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end
end
