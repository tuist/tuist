defmodule AtlasWeb.OverviewLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.Components.Skeleton
  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.Widget

  alias Atlas.TuistOverview
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  @widgets ~w(users active_users organizations projects jobs cache_operations)
  @default_widget "users"

  # Each metric's Postgres/ClickHouse query is measured on its own so the
  # landing page can stream widgets in as they come back rather than waiting
  # for the slowest one. Recent organizations gets its own async slot so the
  # bottom table appears independently too.
  @async_metrics [:users, :active_users, :organizations, :projects, :jobs, :cache_operations]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Overview"))}
  end

  def handle_params(params, _uri, socket) do
    {preset, {start_date, end_date}} = window_from_params(params)
    selected_widget = normalize_widget(params["widget"])

    range_changed? =
      Map.get(socket.assigns, :start_date) != start_date or
        Map.get(socket.assigns, :end_date) != end_date

    socket =
      socket
      |> assign(:selected_preset, preset)
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> assign(:date_range_period, {date_start_of(start_date), date_end_of(end_date)})
      |> assign(:selected_widget, selected_widget)

    socket =
      if range_changed? do
        socket
        |> start_measurements(start_date, end_date)
        |> maybe_start_recent_organizations()
      else
        socket
      end

    {:noreply, socket}
  end

  defp start_measurements(socket, start_date, end_date) do
    range = {start_date, end_date}

    Enum.reduce(@async_metrics, socket, fn metric, acc ->
      key = measurement_assign(metric)

      acc
      |> assign(key, AsyncResult.loading())
      |> start_async(key, fn -> TuistOverview.measure_metric(metric, range) end)
    end)
  end

  # Recent organizations doesn't depend on the date range, so only fetch it
  # once for the LiveView's lifetime.
  defp maybe_start_recent_organizations(socket) do
    case Map.get(socket.assigns, :recent_organizations) do
      nil ->
        socket
        |> assign(:recent_organizations, AsyncResult.loading())
        |> start_async(:recent_organizations, fn -> TuistOverview.recent_organizations() end)

      _existing ->
        socket
    end
  end

  def handle_async(key, {:ok, result}, socket)
      when key in [
             :measurement_users,
             :measurement_active_users,
             :measurement_organizations,
             :measurement_projects,
             :measurement_jobs,
             :measurement_cache_operations,
             :recent_organizations
           ] do
    async = Map.fetch!(socket.assigns, key)
    {:noreply, assign(socket, key, AsyncResult.ok(async, result))}
  end

  def handle_async(key, {:exit, reason}, socket)
      when key in [
             :measurement_users,
             :measurement_active_users,
             :measurement_organizations,
             :measurement_projects,
             :measurement_jobs,
             :measurement_cache_operations,
             :recent_organizations
           ] do
    async = Map.fetch!(socket.assigns, key)
    {:noreply, assign(socket, key, AsyncResult.failed(async, {:exit, reason}))}
  end

  def handle_event(
        "range_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        %{
          "widget" => socket.assigns.selected_widget,
          "range" => "custom",
          "start" => start_date,
          "end" => end_date
        }
      else
        %{"widget" => socket.assigns.selected_widget, "range" => preset}
      end

    {:noreply, push_patch(socket, to: ~p"/?#{query}")}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{current_query(socket) |> Map.put("widget", widget)}")}
  end

  def render(assigns) do
    ~H"""
    <div id="overview">
      <.card title={gettext("Overview")} icon="chart_dots" data-part="tuist-card">
        <:actions>
          <div data-part="overview-actions">
            <.date_picker
              id="overview-date-range-picker"
              label={gettext("Date range")}
              name="overview-date-range"
              presets={date_picker_presets()}
              selected_preset={@selected_preset}
              period={@date_range_period}
              on_period_change="range_changed"
              max={Date.utc_today()}
            >
              <:actions>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  phx-click={
                    JS.dispatch("phx:date-picker-cancel",
                      detail: %{id: "overview-date-range-picker"}
                    )
                  }
                />
                <.button
                  label={gettext("Apply")}
                  phx-click={
                    JS.dispatch("phx:date-picker-apply",
                      detail: %{id: "overview-date-range-picker"}
                    )
                  }
                />
              </:actions>
            </.date_picker>
          </div>
        </:actions>
        <.card_section data-part="tuist-section">
          <div data-part="widgets">
            <.metric_widget
              id="overview-widget-users"
              widget="users"
              title={gettext("Users")}
              measurement={@measurement_users}
              legend_color="primary"
              selected={@selected_widget == "users"}
              tooltip_description={gettext("Total number of Tuist user accounts.")}
            />
            <.metric_widget
              id="overview-widget-active-users"
              widget="active_users"
              title={gettext("Active users")}
              measurement={@measurement_active_users}
              legend_color="quaternary"
              selected={@selected_widget == "active_users"}
              tooltip_description={
                gettext(
                  "Users who ran a Tuist command or Xcode build on an average day of the selected range. CI runs carry no user, so they are not counted."
                )
              }
            />
            <.metric_widget
              id="overview-widget-organizations"
              widget="organizations"
              title={gettext("Organizations")}
              measurement={@measurement_organizations}
              legend_color="secondary"
              selected={@selected_widget == "organizations"}
              tooltip_description={gettext("Total number of Tuist organizations.")}
            />
            <.metric_widget
              id="overview-widget-projects"
              widget="projects"
              title={gettext("Projects")}
              measurement={@measurement_projects}
              legend_color="attention"
              selected={@selected_widget == "projects"}
              tooltip_description={gettext("Total number of Tuist projects across every account.")}
            />
            <.metric_widget
              id="overview-widget-jobs"
              widget="jobs"
              title={gettext("CI jobs")}
              measurement={@measurement_jobs}
              legend_color="success"
              selected={@selected_widget == "jobs"}
              tooltip_description={
                gettext(
                  "CI jobs Tuist ran on hosted runners for customers within the selected range."
                )
              }
            />
            <.metric_widget
              id="overview-widget-cache-operations"
              widget="cache_operations"
              title={gettext("Cache operations")}
              measurement={@measurement_cache_operations}
              legend_color="neutral"
              selected={@selected_widget == "cache_operations"}
              tooltip_description={
                gettext("Xcode, Bazel and Gradle cache events served within the selected range.")
              }
            />
          </div>
        </.card_section>
        <.card_section data-part="chart-section">
          {render_selected_chart(assigns)}
        </.card_section>
      </.card>

      <.card
        title={gettext("Recent organizations")}
        icon="building"
        data-part="recent-organizations-card"
      >
        <.card_section data-part="recent-organizations-section">
          {render_recent_organizations(assigns)}
        </.card_section>
      </.card>
    </div>
    """
  end

  defp render_recent_organizations(assigns) do
    case assigns.recent_organizations do
      %AsyncResult{ok?: true, result: {:ok, rows}} ->
        assigns = assign(assigns, :rows, rows)

        ~H"""
        <.table id="overview-recent-organizations-table" rows={@rows}>
          <:col :let={row} label={gettext("Organization")}>
            <.text_cell label={row.name} />
          </:col>
          <:col :let={row} label={gettext("Created")}>
            <.text_cell label={format_created_at(row.created_at)} />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="building"
              title={gettext("No organizations yet")}
              subtitle={gettext("New Tuist organizations will show up here as they are created.")}
            />
          </:empty_state>
        </.table>
        """

      %AsyncResult{ok?: true, result: {:error, :not_configured}} ->
        ~H"""
        <div data-part="recent-organizations-empty">
          {gettext("Tuist server is not connected.")}
        </div>
        """

      %AsyncResult{ok?: true, result: {:error, _reason}} ->
        ~H"""
        <div data-part="recent-organizations-empty">
          {gettext("Recent organizations are temporarily unavailable.")}
        </div>
        """

      %AsyncResult{failed: failure} when not is_nil(failure) ->
        ~H"""
        <div data-part="recent-organizations-empty">
          {gettext("Recent organizations are temporarily unavailable.")}
        </div>
        """

      _loading ->
        ~H"""
        <div data-part="recent-organizations-skeleton">
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
        </div>
        """
    end
  end

  defp format_created_at(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_created_at(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %-d, %Y")
  defp format_created_at(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
  defp format_created_at(_), do: "-"

  attr :id, :string, required: true
  attr :widget, :string, required: true
  attr :title, :string, required: true
  attr :measurement, :any, required: true
  attr :legend_color, :string, required: true
  attr :selected, :boolean, default: false
  attr :tooltip_description, :string, default: nil

  defp metric_widget(assigns) do
    case assigns.measurement do
      %AsyncResult{ok?: true, result: {:ok, %{current_value: value, delta_pct: delta}}} ->
        assigns =
          assigns
          |> assign(:value, format_count(value))
          |> assign(:delta, delta)

        ~H"""
        <.widget
          id={@id}
          title={@title}
          value={@value}
          legend_color={@legend_color}
          tooltip_description={@tooltip_description}
          trend_value={@delta && @delta / 1}
          trend_label={gettext("vs prev.")}
          phx_click="select_widget"
          phx_value_widget={@widget}
          selected={@selected}
        />
        """

      %AsyncResult{ok?: true, result: {:error, :not_configured}} ->
        ~H"""
        <.widget
          id={@id}
          title={@title}
          legend_color={@legend_color}
          tooltip_description={@tooltip_description}
          empty
          empty_label={gettext("Not connected")}
          phx_click="select_widget"
          phx_value_widget={@widget}
          selected={@selected}
        />
        """

      %AsyncResult{ok?: true, result: {:error, _reason}} ->
        ~H"""
        <.widget
          id={@id}
          title={@title}
          legend_color="destructive"
          tooltip_description={@tooltip_description}
          empty
          empty_label={gettext("Unavailable")}
          phx_click="select_widget"
          phx_value_widget={@widget}
          selected={@selected}
        />
        """

      %AsyncResult{failed: failure} when not is_nil(failure) ->
        ~H"""
        <.widget
          id={@id}
          title={@title}
          legend_color="destructive"
          tooltip_description={@tooltip_description}
          empty
          empty_label={gettext("Unavailable")}
          phx_click="select_widget"
          phx_value_widget={@widget}
          selected={@selected}
        />
        """

      _loading ->
        ~H"""
        <.widget
          id={@id}
          title={@title}
          legend_color={@legend_color}
          tooltip_description={@tooltip_description}
          loading
          phx_click="select_widget"
          phx_value_widget={@widget}
          selected={@selected}
        />
        """
    end
  end

  defp render_selected_chart(assigns) do
    measurement = Map.fetch!(assigns, measurement_assign(String.to_existing_atom(assigns.selected_widget)))

    case measurement do
      %AsyncResult{ok?: true, result: {:ok, %{series: [_ | _] = series} = measurement}} ->
        chart_series = chart_series(assigns.selected_widget, series, Map.get(measurement, :trend, []))

        assigns =
          assigns
          |> assign(:series_dates, Enum.map(series, fn {date, _value} -> Date.to_iso8601(date) end))
          |> assign(:chart_series, chart_series)
          |> assign(:chart_type, chart_type(assigns.selected_widget))

        assigns = assign(assigns, :chart_dom_id, chart_dom_id(assigns))

        ~H"""
        <div data-part="chart" id={"overview-chart-wrapper-#{@chart_dom_id}"}>
          <.chart
            id={"overview-chart-#{@chart_dom_id}"}
            type={@chart_type}
            extra_options={chart_options(@series_dates, length(@chart_series) > 1)}
            series={@chart_series}
            show_legend={length(@chart_series) > 1}
            y_axis_min={0}
          />
        </div>
        """

      %AsyncResult{ok?: true} ->
        ~H"""
        <div data-part="chart-empty">
          {gettext("No history available for this metric yet.")}
        </div>
        """

      %AsyncResult{failed: failure} when not is_nil(failure) ->
        ~H"""
        <div data-part="chart-empty">
          {gettext("No history available for this metric yet.")}
        </div>
        """

      _loading ->
        ~H"""
        <div data-part="chart">
          <.skeleton_chart />
        </div>
        """
    end
  end

  # A metric that ships a trend series renders it as a second, flatter line on
  # top of the raw one. The raw series keeps its fill so it still reads as the
  # subject of the chart and the trend as an annotation over it.
  defp chart_series(widget, series, trend) do
    type = chart_type(widget)

    raw = %{
      name: widget_title(widget),
      type: type,
      color: chart_color(widget),
      data: Enum.map(series, fn {date, value} -> [Date.to_iso8601(date), value] end),
      smooth: 0.25,
      symbol: "none",
      areaStyle: %{opacity: 0.15}
    }

    case trend do
      [_ | _] ->
        [
          raw,
          %{
            name: gettext("7-day average"),
            type: "line",
            color: "var:noora-surface-label-primary",
            data: Enum.map(trend, fn {date, value} -> [Date.to_iso8601(date), value] end),
            smooth: 0.25,
            symbol: "none",
            lineStyle: %{width: 2}
          }
        ]

      _none ->
        [raw]
    end
  end

  defp measurement_assign(:users), do: :measurement_users
  defp measurement_assign(:active_users), do: :measurement_active_users
  defp measurement_assign(:organizations), do: :measurement_organizations
  defp measurement_assign(:projects), do: :measurement_projects
  defp measurement_assign(:jobs), do: :measurement_jobs
  defp measurement_assign(:cache_operations), do: :measurement_cache_operations

  defp chart_type("jobs"), do: "bar"
  defp chart_type("cache_operations"), do: "bar"
  defp chart_type(_widget), do: "line"

  defp chart_color("users"), do: "var:noora-chart-primary"
  defp chart_color("active_users"), do: "var:noora-chart-quaternary"
  defp chart_color("organizations"), do: "var:noora-chart-secondary"
  defp chart_color("projects"), do: "var:noora-chart-tertiary"
  defp chart_color("jobs"), do: "var:noora-chart-tertiary"
  defp chart_color("cache_operations"), do: "var:noora-chart-primary"

  defp widget_title("users"), do: "Users"
  defp widget_title("active_users"), do: "Active users"
  defp widget_title("organizations"), do: "Organizations"
  defp widget_title("projects"), do: "Projects"
  defp widget_title("jobs"), do: "CI jobs"
  defp widget_title("cache_operations"), do: "Cache operations"

  # The ECharts hook re-renders in `updated()` when the LiveView patches the
  # embedded options blob, but a same-widget range change re-uses the same DOM
  # id and the diff can be missed. Include the window in the id so any range
  # change remounts the chart cleanly.
  defp chart_dom_id(assigns) do
    "#{assigns.selected_widget}-#{Date.to_iso8601(assigns.start_date)}-#{Date.to_iso8601(assigns.end_date)}"
  end

  defp chart_options([], _legend?), do: %{}

  defp chart_options(dates, legend?) do
    %{
      grid: %{width: "95%", left: "0.4%", right: "3%", height: grid_height(legend?), top: grid_top(legend?)},
      legend: %{textStyle: %{color: "var:noora-surface-label-secondary"}},
      xAxis: %{
        boundaryGap: true,
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
        axisLabel: %{color: "var:noora-surface-label-secondary"}
      },
      tooltip: %{}
    }
  end

  defp grid_top(true), do: "18%"
  defp grid_top(false), do: "8%"

  defp grid_height(true), do: "68%"
  defp grid_height(false), do: "78%"

  defp date_picker_presets do
    Enum.map(TuistOverview.presets(), fn preset ->
      %{id: preset.id, label: preset.label, period: {preset.days, :day}}
    end) ++ [%{id: "custom", label: gettext("Custom")}]
  end

  defp window_from_params(%{"range" => "custom", "start" => start_iso, "end" => end_iso}) do
    with {:ok, start_date} <- parse_iso_date(start_iso),
         {:ok, end_date} <- parse_iso_date(end_iso),
         true <- Date.compare(end_date, start_date) != :lt do
      {"custom", {start_date, end_date}}
    else
      _other -> default_window()
    end
  end

  defp window_from_params(%{"range" => preset}) when is_binary(preset) do
    case TuistOverview.preset(preset) do
      %{id: id, days: days} -> {id, window_for_days(days)}
      nil -> default_window()
    end
  end

  defp window_from_params(_params), do: default_window()

  defp default_window do
    preset = TuistOverview.default_preset()
    %{days: days} = TuistOverview.preset(preset)
    {preset, window_for_days(days)}
  end

  defp window_for_days(days) do
    today = Date.utc_today()
    {Date.add(today, -(days - 1)), today}
  end

  defp parse_iso_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, date}

      {:error, _reason} ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _off} -> {:ok, DateTime.to_date(dt)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp parse_iso_date(_value), do: :error

  defp normalize_widget(value) when value in @widgets, do: value
  defp normalize_widget(_value), do: @default_widget

  defp current_query(socket) do
    case socket.assigns.selected_preset do
      "custom" ->
        %{
          "range" => "custom",
          "start" => Date.to_iso8601(socket.assigns.start_date),
          "end" => Date.to_iso8601(socket.assigns.end_date)
        }

      preset ->
        %{"range" => preset}
    end
  end

  defp date_start_of(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp date_end_of(%Date{} = date), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

  defp format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end
end
