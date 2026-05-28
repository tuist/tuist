defmodule TuistWeb.UsageLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Kura.Usage
  alias Tuist.Projects
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.CldrHelpers
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @hourly_bucket_max_hours 36

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: current_user}} = socket) do
    if Authorization.authorize(:projects_read, current_user, account) != :ok or
         not FeatureFlags.kura_enabled?(account) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_usage", "The page you are looking for doesn't exist or has been moved.")
    end

    accessible_projects = Projects.list_accessible_projects(account, preload: [])
    projects_with_usage_ids = account.id |> Usage.project_ids_with_usage() |> MapSet.new()

    projects =
      accessible_projects
      |> Enum.filter(&MapSet.member?(projects_with_usage_ids, &1.id))
      |> Enum.sort_by(& &1.name)

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard_usage", "Usage")} · #{account.name} · Tuist")
     |> assign(:projects, projects)}
  end

  @widgets ["egress", "ingress", "requests"]

  @impl true
  def handle_params(params, uri, %{assigns: %{selected_account: account, projects: projects}} = socket) do
    %{preset: preset, period: {start_dt, end_dt} = period} =
      DatePicker.date_picker_params(params, "usage", default_preset: "last-30-days")

    project_handle = params["project"] || "any"
    project_id = project_id_for_handle(projects, project_handle)
    bucket = bucket_for_window(start_dt, end_dt)
    selected_widget = widget_param(params["widget"])

    base_opts =
      case project_id do
        nil -> [bucket: bucket]
        id -> [bucket: bucket, project_id: id]
      end

    egress_opts = Keyword.merge(base_opts, direction: "egress", metric: :bytes)
    ingress_opts = Keyword.merge(base_opts, direction: "ingress", metric: :bytes)
    requests_opts = Keyword.put(base_opts, :metric, :requests)

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:project_handle, project_handle)
     |> assign(:bucket, bucket)
     |> assign(:analytics_selected_widget, selected_widget)
     |> assign_async(
       [:totals, :egress_series, :ingress_series, :requests_series, :per_node],
       fn ->
         {:ok,
          %{
            totals: Usage.totals(account.id, start_dt, end_dt, base_opts),
            egress_series: Usage.traffic_time_series_by_region(account.id, start_dt, end_dt, egress_opts),
            ingress_series: Usage.traffic_time_series_by_region(account.id, start_dt, end_dt, ingress_opts),
            requests_series: Usage.traffic_time_series_by_region(account.id, start_dt, end_dt, requests_opts),
            per_node: Usage.per_node(account.id, start_dt, end_dt, base_opts)
          }}
       end
     )}
  end

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, push_patch_with_param(socket, "widget", widget)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("usage-date-range", "custom")
        |> Query.put("usage-start-date", start_date)
        |> Query.put("usage-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "usage-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{socket.assigns.selected_account.name}/usage?#{query_params}")}
  end

  defp push_patch_with_param(socket, key, value) do
    query = Query.put(socket.assigns.uri.query || "", key, value)
    push_patch(socket, to: "/#{socket.assigns.selected_account.name}/usage?#{query}")
  end

  defp widget_param(widget) when widget in @widgets, do: widget
  defp widget_param(_), do: "egress"

  def project_patch(%URI{} = uri, handle) do
    "?" <> Query.put(uri.query, "project", handle)
  end

  def project_label("any"), do: dgettext("dashboard_usage", "Any")
  def project_label(handle) when is_binary(handle), do: handle

  defp project_id_for_handle(_projects, "any"), do: nil
  defp project_id_for_handle(_projects, nil), do: nil
  defp project_id_for_handle(_projects, ""), do: nil

  defp project_id_for_handle(projects, handle) when is_binary(handle) do
    case Enum.find(projects, &(&1.name == handle)) do
      nil -> nil
      project -> project.id
    end
  end

  defp bucket_for_window(start_dt, end_dt) do
    if DateTime.diff(end_dt, start_dt, :hour) <= @hourly_bucket_max_hours, do: :hour, else: :day
  end

  @doc """
  echarts `extra_options` for the traffic chart. The y-axis + tooltip
  formatter depend on which widget is selected: bytes for egress/ingress,
  raw count for requests.
  """
  def traffic_chart_options(dates, analytics_preset, bucket, selected_widget) do
    {axis_formatter, tooltip_format} = formatters_for(selected_widget)

    %{
      legend: %{
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
        icon:
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      grid: %{width: "97%", left: "0.4%", height: "78%", top: "8%"},
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
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: axis_formatter
        }
      },
      tooltip:
        if analytics_preset == "last-24-hours" or bucket == :hour do
          Map.put(tooltip_format, :dateFormat, "hour")
        else
          tooltip_format
        end
    }
  end

  defp formatters_for("requests"), do: {nil, %{}}
  defp formatters_for(_), do: {"fn:formatBytes", %{valueFormat: "fn:formatBytes"}}

  @doc """
  Picks the right series for the currently selected widget so the template
  doesn't have to branch on three different async assigns.
  """
  def series_for(socket_assigns, "egress"), do: socket_assigns.egress_series
  def series_for(socket_assigns, "ingress"), do: socket_assigns.ingress_series
  def series_for(socket_assigns, "requests"), do: socket_assigns.requests_series

  @region_colors ["primary", "secondary", "tertiary", "p50", "p90", "p99", "warning", "destructive"]

  @doc """
  Builds one echarts series per region. Stable-orders regions by total bytes
  so the colour assignment stays consistent across patches that don't change
  the data, but freshest legend chips first when traffic shifts.
  """
  def traffic_chart_series(time_series) do
    time_series
    |> Enum.with_index()
    |> Enum.map(fn {%{region: region, dates: dates, values: values}, idx} ->
      color_key = Enum.at(@region_colors, rem(idx, length(@region_colors)))

      %{
        color: "var:noora-chart-#{color_key}",
        data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1),
        name: region_label(region),
        type: "line",
        smooth: 0.1,
        symbol: "none"
      }
    end)
  end

  def region_label(""), do: dgettext("dashboard_usage", "Unknown")
  def region_label(nil), do: dgettext("dashboard_usage", "Unknown")
  def region_label(region) when is_binary(region), do: region

  def format_bytes(value), do: ByteFormatter.format_bytes(value || 0)
  def format_count(value) when is_integer(value), do: CldrHelpers.format_number(value)
  def format_count(_), do: CldrHelpers.format_number(0)

  def empty_label, do: dgettext("dashboard_usage", "No cache traffic in this window yet")
end
