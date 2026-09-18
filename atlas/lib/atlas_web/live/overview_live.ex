defmodule AtlasWeb.OverviewLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.Widget

  alias Atlas.TuistOverview
  alias Phoenix.LiveView.JS

  @widgets ~w(users organizations projects jobs cache_operations)
  @default_widget "users"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Overview"))}
  end

  def handle_params(params, _uri, socket) do
    {preset, {start_date, end_date}} = window_from_params(params)
    selected_widget = normalize_widget(params["widget"])

    measurements = TuistOverview.measure({start_date, end_date})
    recent_organizations = TuistOverview.recent_organizations()

    {:noreply,
     socket
     |> assign(:selected_preset, preset)
     |> assign(:start_date, start_date)
     |> assign(:end_date, end_date)
     |> assign(:date_range_period, {date_start_of(start_date), date_end_of(end_date)})
     |> assign(:selected_widget, selected_widget)
     |> assign(:measurements, measurements)
     |> assign(:recent_organizations, recent_organizations)}
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
              measurement={@measurements.users}
              legend_color="primary"
              selected={@selected_widget == "users"}
              tooltip_description={gettext("Total number of Tuist user accounts.")}
            />
            <.metric_widget
              id="overview-widget-organizations"
              widget="organizations"
              title={gettext("Organizations")}
              measurement={@measurements.organizations}
              legend_color="secondary"
              selected={@selected_widget == "organizations"}
              tooltip_description={gettext("Total number of Tuist organizations.")}
            />
            <.metric_widget
              id="overview-widget-projects"
              widget="projects"
              title={gettext("Projects")}
              measurement={@measurements.projects}
              legend_color="attention"
              selected={@selected_widget == "projects"}
              tooltip_description={gettext("Total number of Tuist projects across every account.")}
            />
            <.metric_widget
              id="overview-widget-jobs"
              widget="jobs"
              title={gettext("CI jobs")}
              measurement={@measurements.jobs}
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
              measurement={@measurements.cache_operations}
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
      {:ok, rows} ->
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

      {:error, :not_configured} ->
        ~H"""
        <div data-part="recent-organizations-empty">
          {gettext("Tuist server is not connected.")}
        </div>
        """

      {:error, _reason} ->
        ~H"""
        <div data-part="recent-organizations-empty">
          {gettext("Recent organizations are temporarily unavailable.")}
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
      {:ok, %{current_value: value, delta_pct: delta}} ->
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

      {:error, :not_configured} ->
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

      {:error, _reason} ->
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
    end
  end

  defp render_selected_chart(assigns) do
    case Map.get(assigns.measurements, String.to_existing_atom(assigns.selected_widget)) do
      {:ok, %{series: [_ | _] = series}} ->
        assigns =
          assigns
          |> assign(:series_dates, Enum.map(series, fn {date, _value} -> Date.to_iso8601(date) end))
          |> assign(:series_data, Enum.map(series, fn {date, value} -> [Date.to_iso8601(date), value] end))
          |> assign(:chart_type, chart_type(assigns.selected_widget))
          |> assign(:chart_color, chart_color(assigns.selected_widget))
          |> assign(:chart_title, widget_title(assigns.selected_widget))

        assigns = assign(assigns, :chart_dom_id, chart_dom_id(assigns))

        ~H"""
        <div data-part="chart" id={"overview-chart-wrapper-#{@chart_dom_id}"}>
          <.chart
            id={"overview-chart-#{@chart_dom_id}"}
            type={@chart_type}
            extra_options={chart_options(@series_dates)}
            series={[
              %{
                name: @chart_title,
                type: @chart_type,
                color: @chart_color,
                data: @series_data,
                smooth: 0.25,
                symbol: "none",
                areaStyle: %{opacity: 0.15}
              }
            ]}
            y_axis_min={0}
          />
        </div>
        """

      _other ->
        ~H"""
        <div data-part="chart-empty">
          {gettext("No history available for this metric yet.")}
        </div>
        """
    end
  end

  defp chart_type("jobs"), do: "bar"
  defp chart_type("cache_operations"), do: "bar"
  defp chart_type(_widget), do: "line"

  defp chart_color("users"), do: "var:noora-chart-primary"
  defp chart_color("organizations"), do: "var:noora-chart-secondary"
  defp chart_color("projects"), do: "var:noora-chart-tertiary"
  defp chart_color("jobs"), do: "var:noora-chart-tertiary"
  defp chart_color("cache_operations"), do: "var:noora-chart-primary"

  defp widget_title("users"), do: "Users"
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

  defp chart_options([]), do: %{}

  defp chart_options(dates) do
    %{
      grid: %{width: "95%", left: "0.4%", right: "3%", height: "78%", top: "8%"},
      legend: %{show: false},
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
