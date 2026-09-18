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
    preset = normalize_preset(params["range"])
    {start_date, end_date} = window_for_preset(preset)
    selected_widget = normalize_widget(params["widget"])

    measurements = TuistOverview.measure({start_date, end_date})

    {:noreply,
     socket
     |> assign(:selected_preset, preset)
     |> assign(:start_date, start_date)
     |> assign(:end_date, end_date)
     |> assign(:selected_widget, selected_widget)
     |> assign(:measurements, measurements)}
  end

  def handle_event("select_range", %{"range" => preset}, socket) do
    {:noreply, push_patch(socket, to: build_path(preset, socket.assigns.selected_widget))}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket.assigns.selected_preset, widget))}
  end

  def render(assigns) do
    ~H"""
    <div id="overview">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Overview")}</h1>
          <p data-part="description">
            {gettext(
              "A live snapshot of Tuist pulled straight from the server. Click any widget to see how it evolved."
            )}
          </p>
        </div>
      </div>

      <.card title={gettext("Tuist")} icon="chart_dots" data-part="tuist-card">
        <:actions>
          <div data-part="overview-actions">
            <.range_dropdown selected_preset={@selected_preset} />
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
              title={gettext("Jobs")}
              measurement={@measurements.jobs}
              legend_color="success"
              selected={@selected_widget == "jobs"}
              tooltip_description={
                gettext("Runner jobs Tuist scheduled for customers within the selected range.")
              }
              value_over_window
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
              value_over_window
            />
          </div>
        </.card_section>
        <.card_section data-part="chart-section">
          {render_selected_chart(assigns)}
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :selected_preset, :string, required: true

  defp range_dropdown(assigns) do
    presets = TuistOverview.presets()
    selected = Enum.find(presets, &(&1.id == assigns.selected_preset)) || hd(presets)
    assigns = assign(assigns, presets: presets, selected: selected)

    ~H"""
    <div
      id="overview-range-dropdown"
      class="account-dropdown"
      phx-hook="NooraDropdown"
      data-loop-focus
      data-close-on-select
      data-positioning-offset-main-axis={6}
    >
      <button data-part="trigger">
        <.button
          label={gettext("Range: %{label}", label: @selected.label)}
          variant="secondary"
          size="small"
        >
          <:icon_right><.icon name="chevron_down" /></:icon_right>
        </.button>
      </button>
      <div data-part="positioner">
        <div data-part="content">
          <div data-part="actions">
            <button
              :for={preset <- @presets}
              type="button"
              phx-click={JS.push("select_range", value: %{range: preset.id})}
              data-selected={preset.id == @selected.id}
              data-part="dropdown-item"
            >
              {preset.label}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :widget, :string, required: true
  attr :title, :string, required: true
  attr :measurement, :any, required: true
  attr :legend_color, :string, required: true
  attr :selected, :boolean, default: false
  attr :tooltip_description, :string, default: nil
  attr :value_over_window, :boolean, default: false

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
          trend_label={gettext("vs previous period")}
          description={if @value_over_window, do: gettext("Within selected range"), else: nil}
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

        ~H"""
        <div data-part="chart" id={"overview-chart-wrapper-#{@selected_widget}"}>
          <.chart
            id={"overview-chart-#{@selected_widget}"}
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
  defp widget_title("jobs"), do: "Jobs"
  defp widget_title("cache_operations"), do: "Cache operations"

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

  defp build_path(preset, widget) do
    ~p"/?#{%{"range" => preset, "widget" => widget}}"
  end

  defp normalize_preset(value) do
    case TuistOverview.preset(value) do
      %{id: id} -> id
      nil -> TuistOverview.default_preset()
    end
  end

  defp normalize_widget(value) when value in @widgets, do: value
  defp normalize_widget(_value), do: @default_widget

  defp window_for_preset(preset_id) do
    %{days: days} = TuistOverview.preset(preset_id) || TuistOverview.preset(TuistOverview.default_preset())
    today = Date.utc_today()
    {Date.add(today, -(days - 1)), today}
  end

  defp format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end
end
