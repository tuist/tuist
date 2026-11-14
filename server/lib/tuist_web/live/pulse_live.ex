defmodule TuistWeb.PulseLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Components.Skeleton

  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Pulse

  @refresh_interval 15_000
  @table_params ~w(query range page page_size sort_by sort_order search end_at)

  def mount(_params, _session, socket) do
    authorize!(socket)
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok, assign(socket, telemetry: AsyncResult.loading(), analytics: AsyncResult.loading())}
  end

  def handle_params(params, uri, socket) do
    authorize!(socket)
    signal = Atom.to_string(socket.assigns.live_action)
    filters = define_filters(signal)
    filter_keys = Enum.flat_map(filters, &["filter_#{&1.id}_op", "filter_#{&1.id}_val"])
    params = Map.take(params, @table_params ++ ~w(widget chart_type) ++ filter_keys)
    params = Map.put_new(params, "query", Pulse.default_query(signal))
    params = Map.put_new(params, "range", "1h")
    widgets = widgets(signal)
    widget = Enum.find(widgets, &(&1.id == params["widget"])) || hd(widgets)
    chart_types = chart_types(widget)
    chart_type = if params["chart_type"] in chart_types, do: params["chart_type"], else: hd(chart_types)
    params = if Map.has_key?(params, "chart_type"), do: Map.put(params, "chart_type", chart_type), else: params
    sort_by = params["sort_by"] || default_sort(signal)
    sort_order = params["sort_order"] || default_order(sort_by)

    table_end = table_end(socket.assigns, signal, params)

    {:noreply,
     socket
     |> assign(:signal, signal)
     |> assign(:uri, URI.parse(uri))
     |> assign(:available_filters, filters)
     |> assign(:active_filters, Filter.Operations.decode_filters_from_query(params, filters))
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:table_end, table_end)
     |> assign(:show_query, socket.assigns[:show_query] || false)
     |> assign(:widgets, widgets)
     |> assign(:widget, widget)
     |> assign(:chart_types, chart_types)
     |> assign(:chart_type, chart_type)
     |> assign(:head_title, "#{title(signal)} · #{socket.assigns.selected_account.name} · Tuist")
     |> assign(:params, params)
     |> assign(:form, to_form(params, as: :pulse))
     |> load()}
  end

  defp table_end(assigns, signal, params) do
    params["end_at"] ||
      if(assigns[:signal] == signal && assigns[:params]["range"] == params["range"],
        do: assigns.table_end,
        else: DateTime.to_iso8601(DateTime.utc_now())
      )
  end

  def handle_event("query", %{"pulse" => params}, socket) do
    authorize!(socket)

    {:noreply,
     push_patch(socket,
       to:
         signal_path(
           socket.assigns.selected_account,
           socket.assigns.signal,
           socket.assigns.params |> Map.merge(Map.take(params, ~w(query search))) |> Map.delete("page")
         )
     )}
  end

  def handle_event("toggle_query", _params, socket) do
    authorize!(socket)
    {:noreply, assign(socket, :show_query, !socket.assigns.show_query)}
  end

  def handle_event("resume_live", _params, socket) do
    authorize!(socket)
    params = Map.drop(socket.assigns.params, ~w(page end_at))
    socket = assign(socket, :table_end, DateTime.to_iso8601(DateTime.utc_now()))
    {:noreply, push_patch(socket, to: signal_path(socket.assigns.selected_account, socket.assigns.signal, params))}
  end

  def handle_event("add_filter", %{"value" => id}, socket) do
    authorize!(socket)

    if Enum.any?(socket.assigns.available_filters, &(&1.id == id)) do
      params = Filter.Operations.add_filter_to_query(id, socket, socket.assigns.params)

      {:noreply,
       socket
       |> push_patch(to: signal_path(socket.assigns.selected_account, socket.assigns.signal, Map.delete(params, "page")))
       |> push_event("open-popover", %{id: "filter-#{id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", params, socket) do
    authorize!(socket)
    params = Filter.Operations.update_filters_in_query(params, socket, socket.assigns.params)

    {:noreply,
     socket
     |> push_patch(to: signal_path(socket.assigns.selected_account, socket.assigns.signal, Map.delete(params, "page")))
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    authorize!(socket)
    widget = Enum.find(socket.assigns.widgets, &(&1.id == widget)) || hd(socket.assigns.widgets)
    params = Map.put(socket.assigns.params, "widget", widget.id)

    params =
      if Map.has_key?(params, "chart_type") && params["chart_type"] not in chart_types(widget),
        do: Map.put(params, "chart_type", hd(chart_types(widget))),
        else: params

    {:noreply,
     push_patch(socket,
       to:
         signal_path(
           socket.assigns.selected_account,
           socket.assigns.signal,
           params
         ),
       replace: true
     )}
  end

  def handle_event("select_chart_type", %{"type" => type}, socket) do
    authorize!(socket)

    if type in socket.assigns.chart_types do
      {:noreply,
       push_patch(socket,
         to:
           signal_path(
             socket.assigns.selected_account,
             socket.assigns.signal,
             Map.put(socket.assigns.params, "chart_type", type)
           ),
         replace: true
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh, socket) do
    authorize!(socket)
    Process.send_after(self(), :refresh, @refresh_interval)

    socket =
      if live_table?(socket.assigns) && !socket.assigns.telemetry.loading,
        do: assign(socket, :table_end, DateTime.to_iso8601(DateTime.utc_now())),
        else: socket

    {:noreply, load(socket, true)}
  end

  defp authorize!(socket) do
    if !Pulse.authorized?(socket.assigns.current_user, socket.assigns.selected_account) do
      raise TuistWeb.Errors.NotFoundError, "Not found"
    end
  end

  defp load(socket, force \\ false) do
    user = socket.assigns.current_user
    account = socket.assigns.selected_account
    signal = socket.assigns.signal
    params = socket.assigns.params

    Enum.reduce(
      [
        {:telemetry, :query, table_inputs(socket.assigns)},
        {:analytics, :analytics, Map.take(params, ~w(range))}
      ],
      socket,
      fn {key, function, inputs}, socket ->
        load_key = {signal, inputs}
        previous = socket.assigns[:load_keys][key]
        result = socket.assigns[key]

        refresh? = force && (key == :analytics || live_table?(socket.assigns))

        if reload?(socket, previous, load_key, result, refresh?) do
          socket
          |> cancel_async(key)
          |> assign(:load_keys, Map.put(socket.assigns[:load_keys] || %{}, key, load_key))
          |> assign_async(
            key,
            fn -> load_result(key, function, [user, account, signal, inputs]) end,
            reset: previous != nil && elem(previous, 0) != signal
          )
        else
          socket
        end
      end
    )
  end

  defp reload?(socket, previous, load_key, result, refresh?) do
    connected?(socket) && (previous != load_key || (!result.loading && (refresh? || result.failed)))
  end

  defp load_result(key, function, arguments) do
    case apply(Pulse, function, arguments) do
      {:ok, result} -> {:ok, %{key => result}}
      {:error, reason} -> {:error, reason}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="pulse" data-signal={@signal}>
      <div data-part="filters">
        <.button
          :if={!live_table?(assigns)}
          id="pulse-resume-live"
          variant="secondary"
          label={dgettext("dashboard_pulse", "Resume live")}
          phx-click="resume_live"
        />
        <.dropdown
          id="pulse-range"
          label={range_label(@params["range"])}
          secondary_text={dgettext("dashboard_pulse", "Period:")}
        >
          <.dropdown_item
            :for={range <- ~w(15m 1h 6h 24h)}
            value={range}
            label={range_label(range)}
            data-selected={@params["range"] == range}
            patch={
              signal_path(
                @selected_account,
                @signal,
                @params |> Map.drop(~w(page end_at)) |> Map.put("range", range)
              )
            }
          />
        </.dropdown>
      </div>
      <.async_card
        :let={ready?}
        id="pulse-analytics"
        results={[@analytics]}
        title={dgettext("dashboard", "Analytics")}
        icon="chart_arcs"
        data-part="analytics-card"
        data-widget={@widget.id}
        chart_frame="cache"
      >
        <div data-part="widgets">
          <.widget
            :for={widget <- @widgets}
            id={"pulse-widget-#{widget.id}"}
            title={widget.title}
            description={widget.description}
            loading={!ready?}
            value={if ready?, do: widget_value(metric(@analytics.result, widget.id))}
            trend_value={if ready?, do: trend(metric(@analytics.result, widget.id))}
            trend_value_label={if ready?, do: trend_value_label(metric(@analytics.result, widget.id))}
            trend_type={trend_type(@signal, widget.id)}
            trend_label={trend_label(@params["range"])}
            selected={@widget.id == widget.id}
            legend_color={widget.color}
            phx_click="select_widget"
            phx_value_widget={widget.id}
          />
        </div>
        <.card_section data-part="analytics-card-chart-section" data-chart-frame="cache">
          <div
            :if={length(@chart_types) > 1}
            id="pulse-chart-type-controls"
            data-part="chart-controls"
          >
            <.chart_type_toggle
              id="pulse-chart-type"
              chart_type={@chart_type}
              chart_types={@chart_types}
              chart_type_event="select_chart_type"
              uri={@uri}
            />
          </div>
          <.skeleton_chart :if={!ready?} height="200px" />
          <%= if ready? do %>
            <p :for={warning <- @analytics.result.warnings} data-part="warning" role="status">
              {warning}
            </p>
            <%= if chart_available?(metric(@analytics.result, @widget.id)) do %>
              <p :if={@widget.id == "duration_p95"} data-part="chart-description">
                {dgettext(
                  "dashboard_pulse",
                  "Each point is the p95 span duration for one interval, not an individual span."
                )}
              </p>
              <.chart
                id="pulse-chart"
                type={@chart_type}
                series={chart_series(metric(@analytics.result, @widget.id), @widget, @chart_type)}
                labels={[]}
                extra_options={chart_options(@widget, @chart_type)}
              />
            <% else %>
              <.empty_card_section
                id="pulse-chart-empty"
                title={dgettext("dashboard_pulse", "No measurements in this period")}
                data-part="analytics-chart-empty"
              >
                <:image>
                  <img src={~p"/images/empty_line_chart_light.png"} data-theme="light" />
                  <img src={~p"/images/empty_line_chart_dark.png"} data-theme="dark" />
                </:image>
              </.empty_card_section>
            <% end %>
          <% end %>
        </.card_section>
      </.async_card>
      <.card
        id="pulse-results"
        title={title(@signal)}
        icon={signal_icon(@signal)}
        aria-busy={to_string(!!@telemetry.loading)}
      >
        <.card_section data-part="table-section">
          <div data-part="table-toolbar">
            <.form
              id="pulse-query-form"
              for={@form}
              phx-change="query"
              phx-submit="query"
              phx-debounce="300"
              autocomplete="off"
              data-part="query-form"
            >
              <div data-part="query-input">
                <.text_input
                  id="pulse-query"
                  field={@form[:search]}
                  type="search"
                  placeholder={dgettext("dashboard_pulse", "Search...")}
                  aria-label={dgettext("dashboard_pulse", "Search telemetry")}
                  show_suffix={false}
                />
              </div>
            </.form>
            <.dropdown
              id="pulse-sort-by"
              label={sort_label(@signal, @sort_by)}
              secondary_text={dgettext("dashboard", "Sort by:")}
            >
              <.dropdown_item
                :for={{field, label} <- sort_options(@signal)}
                value={field}
                label={label}
                patch={sort_patch(assigns, field)}
                data-selected={@sort_by == field}
              >
                <:right_icon><.check /></:right_icon>
              </.dropdown_item>
            </.dropdown>
            <.filter_dropdown
              id="pulse-filter-dropdown"
              label={dgettext("dashboard", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
            <.button
              id="pulse-toggle-query"
              variant="secondary"
              label={query_language(@signal)}
              phx-click="toggle_query"
              aria-expanded={to_string(@show_query)}
            >
              <:icon_left><.devices_code /></:icon_left>
            </.button>
          </div>
          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <.form
            :if={@show_query}
            id="pulse-expression-form"
            for={@form}
            phx-submit="query"
            autocomplete="off"
            data-part="expression-form"
          >
            <.text_input
              id="pulse-expression"
              field={@form[:query]}
              label={query_language(@signal)}
              show_suffix={false}
            />
            <.button type="submit" label={dgettext("dashboard_pulse", "Run query")} />
          </.form>
          <%= cond do %>
            <% @telemetry.failed -> %>
              <.error_state
                id="pulse-error"
                role="alert"
                title={dgettext("dashboard_pulse", "Telemetry unavailable")}
                subtitle={error_message(@telemetry.failed)}
              />
            <% !@telemetry.ok? -> %>
              <div data-part="loading">
                <.skeleton_chart height="200px" />
              </div>
            <% true -> %>
              <p :for={warning <- @telemetry.result.warnings} data-part="warning" role="status">
                {warning}
              </p>
              <%= if @telemetry.result.rows == [] do %>
                <div id="pulse-empty">
                  <.table_empty_state
                    icon={signal_icon(@signal)}
                    title={
                      dgettext("dashboard_pulse", "No telemetry matches this query and time range.")
                    }
                  />
                </div>
              <% else %>
                <.table
                  id="pulse-table"
                  rows={Enum.with_index(@telemetry.result.rows)}
                  row_key={fn {_, index} -> "pulse-row-#{index}" end}
                >
                  <:col
                    :let={{row, _}}
                    :for={column <- columns(@signal)}
                    label={column.label}
                    patch={if sortable?(@signal, column.key), do: sort_patch(assigns, column.key)}
                    sort_order={@sort_by == column.key && @sort_order}
                  >
                    <.text_cell label={cell(row, column.key)} data-column={column.key} />
                  </:col>
                </.table>
              <% end %>
              <nav
                :if={
                  @telemetry.result.meta["has_previous_page"] ||
                    @telemetry.result.meta["has_next_page"]
                }
                class="tuist-pagination"
                aria-label={dgettext("dashboard_pulse", "Telemetry pages")}
              >
                <.button
                  id="pulse-previous-page"
                  variant="secondary"
                  label={dgettext("dashboard", "Prev")}
                  disabled={!@telemetry.result.meta["has_previous_page"]}
                  patch={page_patch(assigns, -1)}
                >
                  <:icon_left><.chevron_left /></:icon_left>
                </.button>
                <.button
                  id="pulse-next-page"
                  variant="secondary"
                  label={dgettext("dashboard", "Next")}
                  disabled={!@telemetry.result.meta["has_next_page"]}
                  patch={page_patch(assigns, 1)}
                >
                  <:icon_right><.chevron_right /></:icon_right>
                </.button>
              </nav>
          <% end %>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp metric(analytics, id), do: Enum.find(analytics.widgets, &(&1.id == id))
  defp widget_value(%{value: nil}), do: dgettext("dashboard", "No data")
  defp widget_value(%{value: value, unit: :milliseconds}), do: "#{format_number(value, fractional_digits: 1)} ms"
  defp widget_value(%{value: value}), do: format_number(value, fractional_digits: 0)
  defp chart_available?(metric), do: Enum.any?(metric.points, fn [_, value] -> is_number(value) end)

  defp trend(%{value: current, previous_value: previous}) when is_number(current) and is_number(previous) do
    if previous == 0, do: current * 1.0, else: (current - previous) / previous * 100
  end

  defp trend(_metric), do: nil

  defp trend_value_label(%{value: current, previous_value: previous} = metric)
       when is_number(current) and current > 0 and previous == 0, do: "+#{widget_value(metric)}"

  defp trend_value_label(_metric), do: nil

  defp trend_type("metrics", "healthy"), do: :regular
  defp trend_type("metrics", "unhealthy"), do: :inverse
  defp trend_type(_signal, id) when id in ~w(errors warnings duration_p95), do: :inverse
  defp trend_type(_signal, _id), do: :neutral

  defp trend_label("15m"), do: dgettext("dashboard_pulse", "vs previous 15 minutes")
  defp trend_label("6h"), do: dgettext("dashboard_pulse", "vs previous 6 hours")
  defp trend_label("24h"), do: dgettext("dashboard_pulse", "vs previous 24 hours")
  defp trend_label(_range), do: dgettext("dashboard_pulse", "vs previous hour")

  defp chart_types(%{id: id}) when id in ~w(reporting healthy unhealthy), do: ~w(line)
  defp chart_types(%{id: "duration_p95"}), do: ~w(line scatter)
  defp chart_types(_widget), do: ~w(bar line)

  defp chart_series(metric, widget, type) do
    [
      %{
        name: widget.title,
        type: type,
        symbol: "circle",
        symbolSize: if(type == "scatter", do: 7, else: 4),
        barMaxWidth: 32,
        color: "var:noora-chart-#{widget.color}",
        connectNulls: false,
        step: if(widget.id in ~w(reporting healthy unhealthy), do: "end", else: false),
        data: Enum.map(metric.points, fn [time, value] -> [time * 1000, value] end)
      }
    ]
  end

  defp chart_options(widget, type) do
    formatter = if widget.id == "duration_p95", do: "fn:formatMilliseconds", else: "fn:formatNumber"

    %{
      grid: %{left: 8, right: 16, top: 12, bottom: 40, containLabel: true},
      legend: %{
        show: true,
        left: "left",
        top: "bottom",
        icon: "roundRect",
        itemWidth: 8,
        itemHeight: 4,
        textStyle: %{color: "var:noora-surface-label-secondary", fontFamily: "monospace", fontSize: 10}
      },
      xAxis: %{
        type: "time",
        boundaryGap: if(type == "bar", do: ["2%", "2%"], else: false),
        splitNumber: 3,
        axisLabel: %{color: "var:noora-surface-label-secondary", hideOverlap: true}
      },
      yAxis: %{
        min: 0,
        minInterval: if(widget.id == "duration_p95", do: 0, else: 1),
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter},
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}
      },
      tooltip: %{trigger: if(type == "scatter", do: "item", else: "axis"), valueFormat: formatter}
    }
  end

  defp timestamp_label(value) do
    with {ns, ""} <- Integer.parse(to_string(value || "")),
         {:ok, time} <- DateTime.from_unix(div(ns, 1000), :microsecond) do
      Calendar.strftime(time, "%Y-%m-%d %H:%M:%S.%f")
    else
      _ -> "—"
    end
  end

  defp cell(row, "timestamp"), do: timestamp_label(row["timestamp"])

  defp cell(row, key) do
    case row[key] do
      nil -> "—"
      value when is_number(value) -> format_number(value, fractional_digits: 2)
      value when is_map(value) -> Enum.map_join(Enum.sort(value), ", ", fn {k, v} -> "#{k}=#{v}" end)
      value -> to_string(value)
    end
  end

  defp columns("metrics"),
    do: [
      %{key: "name", label: dgettext("dashboard_pulse", "Metric")},
      %{key: "labels", label: dgettext("dashboard_pulse", "Labels")},
      %{key: "value", label: dgettext("dashboard_pulse", "Latest value")}
    ]

  defp columns("traces"),
    do: [
      %{key: "timestamp", label: dgettext("dashboard_pulse", "Started (UTC)")},
      %{key: "service", label: dgettext("dashboard_pulse", "Service")},
      %{key: "name", label: dgettext("dashboard_pulse", "Root span")},
      %{key: "duration_ms", label: dgettext("dashboard_pulse", "Duration (ms)")},
      %{key: "trace_id", label: dgettext("dashboard_pulse", "Trace ID")}
    ]

  defp columns(_),
    do: [
      %{key: "timestamp", label: dgettext("dashboard_pulse", "Time (UTC)")},
      %{key: "service", label: dgettext("dashboard_pulse", "Service")},
      %{key: "level", label: dgettext("dashboard_pulse", "Level")},
      %{key: "message", label: dgettext("dashboard_pulse", "Message")},
      %{key: "trace_id", label: dgettext("dashboard_pulse", "Trace ID")}
    ]

  defp define_filters(signal) do
    fields = if signal == "logs", do: ~w(service level), else: ~w(service)
    labels = %{"service" => dgettext("dashboard_pulse", "Service"), "level" => dgettext("dashboard_pulse", "Level")}

    Enum.map(fields, &%Filter.Filter{id: &1, display_name: labels[&1], type: :text, operator: :==, value: ""})
  end

  defp table_inputs(assigns) do
    assigns.active_filters
    |> Enum.reduce(Map.take(assigns.params, @table_params), fn filter, params ->
      if filter.value in [nil, ""] do
        params
      else
        op = %{:== => "eq", :=~ => "contains", :"!=~" => "not_contains"}[filter.operator]
        params |> Map.put(filter.id, filter.value) |> Map.put("#{filter.id}_op", op)
      end
    end)
    |> Map.put("end_at", assigns.table_end)
  end

  defp default_sort("metrics"), do: "name"
  defp default_sort(_), do: "timestamp"
  defp default_order(field) when field in ~w(name service level), do: "asc"
  defp default_order(_), do: "desc"

  defp sort_options(signal) do
    fields =
      case signal do
        "metrics" -> ~w(name value)
        "logs" -> ~w(timestamp service level)
        "traces" -> ~w(timestamp service name duration_ms)
      end

    for column <- columns(signal), column.key in fields, do: {column.key, column.label}
  end

  defp sortable?(signal, field), do: List.keymember?(sort_options(signal), field, 0)
  defp sort_label(signal, field), do: elem(List.keyfind(sort_options(signal), field, 0, hd(sort_options(signal))), 1)

  defp sort_patch(assigns, field) do
    order =
      if assigns.sort_by == field,
        do: if(assigns.sort_order == "asc", do: "desc", else: "asc"),
        else: default_order(field)

    params = assigns.params |> Map.delete("page") |> Map.put("sort_by", field) |> Map.put("sort_order", order)
    signal_path(assigns.selected_account, assigns.signal, params)
  end

  defp page_patch(assigns, direction) do
    meta = assigns.telemetry.result.meta
    params = assigns.params |> Map.put("page", max(1, meta["page"] + direction)) |> Map.put("end_at", meta["end_at"])
    signal_path(assigns.selected_account, assigns.signal, params)
  end

  defp live_table?(assigns), do: assigns.params["page"] in [nil, "1", 1] && !assigns.params["end_at"]

  defp signal_path(account, "metrics", params), do: ~p"/#{account.name}/~/pulse/metrics?#{params}"
  defp signal_path(account, "logs", params), do: ~p"/#{account.name}/~/pulse/logs?#{params}"
  defp signal_path(account, "traces", params), do: ~p"/#{account.name}/~/pulse/traces?#{params}"
  defp title("metrics"), do: dgettext("dashboard_pulse", "Metrics")
  defp title("logs"), do: dgettext("dashboard_pulse", "Logs")
  defp title("traces"), do: dgettext("dashboard_pulse", "Traces")
  defp query_language("metrics"), do: "PromQL"
  defp query_language(_), do: dgettext("dashboard_pulse", "Text search (* for all)")

  defp signal_icon("metrics"), do: "chart_arcs"
  defp signal_icon("traces"), do: "list_tree"
  defp signal_icon(_), do: "file_text"
  defp range_label("15m"), do: dgettext("dashboard_pulse", "Last 15 minutes")
  defp range_label("6h"), do: dgettext("dashboard_pulse", "Last 6 hours")
  defp range_label("24h"), do: dgettext("dashboard_pulse", "Last 24 hours")
  defp range_label(_), do: dgettext("dashboard_pulse", "Last hour")

  defp widgets("metrics"),
    do: [
      %{
        id: "reporting",
        title: dgettext("dashboard_pulse", "Reporting targets"),
        color: "primary",
        description:
          dgettext(
            "dashboard_pulse",
            "Targets with an up sample at the end of the period. The chart shows the target count over time."
          )
      },
      %{
        id: "healthy",
        title: dgettext("dashboard_pulse", "Healthy targets"),
        color: "secondary",
        description: dgettext("dashboard_pulse", "Targets reporting up = 1 at the end of the period.")
      },
      %{
        id: "unhealthy",
        title: dgettext("dashboard_pulse", "Unhealthy targets"),
        color: "destructive",
        description:
          dgettext(
            "dashboard_pulse",
            "Targets reporting up = 0 at the end of the period. Missing samples are not counted as unhealthy."
          )
      }
    ]

  defp widgets("logs"),
    do: [
      %{
        id: "entries",
        title: dgettext("dashboard_pulse", "Log entries"),
        color: "primary",
        description:
          dgettext(
            "dashboard_pulse",
            "All log entries with a service name in the selected period, independently of table search. The chart shows entries per interval."
          )
      },
      %{
        id: "errors",
        title: dgettext("dashboard_pulse", "Error logs"),
        color: "destructive",
        description:
          dgettext(
            "dashboard_pulse",
            "Log entries labelled error or fatal in the selected period. The chart shows entries per interval."
          )
      },
      %{
        id: "warnings",
        title: dgettext("dashboard_pulse", "Warning logs"),
        color: "amber",
        description:
          dgettext(
            "dashboard_pulse",
            "Log entries labelled warn or warning in the selected period. The chart shows entries per interval."
          )
      }
    ]

  defp widgets("traces"),
    do: [
      %{
        id: "spans",
        title: dgettext("dashboard_pulse", "Spans"),
        color: "primary",
        description:
          dgettext(
            "dashboard_pulse",
            "All recorded spans in the selected period, not distinct traces. The chart shows spans per interval."
          )
      },
      %{
        id: "errors",
        title: dgettext("dashboard_pulse", "Error spans"),
        color: "destructive",
        description:
          dgettext(
            "dashboard_pulse",
            "Spans with error status in the selected period. The chart shows spans per interval."
          )
      },
      %{
        id: "duration_p95",
        title: dgettext("dashboard_pulse", "p95 span duration"),
        color: "secondary",
        description:
          dgettext(
            "dashboard_pulse",
            "Approximate 95th percentile of span durations over the entire selected period, in milliseconds. The chart shows the percentile per interval."
          )
      }
    ]

  defp error_message({:error, :not_configured}),
    do: dgettext("dashboard_pulse", "The Pulse connection is not configured. Contact your administrator.")

  defp error_message({:error, reason}) when reason in [:invalid_query, :invalid_params],
    do: dgettext("dashboard_pulse", "Check your query and time range, then try again.")

  defp error_message({:error, :query_result_limit}),
    do:
      dgettext(
        "dashboard_pulse",
        "This query exceeds the result limit. Narrow the time range or native query and try again."
      )

  defp error_message(_),
    do: dgettext("dashboard_pulse", "Pulse could not complete this query. Adjust the query or refresh to try again.")
end
