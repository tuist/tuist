defmodule TuistWeb.RunnerImageCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.DockerCache
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.RunnersLive
  alias TuistWeb.RunnerVolumesLive

  @page_size 20
  @metrics ["hit_rate", "initialize", "uses"]
  @sort_columns ["repository", "images", "saved_size", "hit_rate", "last_used"]

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    if !(Authorization.authorize(:runners_read, user, account) == :ok and FeatureFlags.runners_enabled?(account)) do
      raise NotFoundError
    end

    if connected?(socket), do: Process.send_after(self(), :refresh, 30_000)

    {:ok,
     assign(socket,
       head_title: "#{dgettext("dashboard_runners", "Image cache")} · #{account.name} · Tuist",
       enabled: FeatureFlags.runner_docker_cache_enabled?(account),
       metric: "hit_rate",
       initialize_percentile: "avg"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{preset: preset, period: period} = RunnerVolumesLive.storage_period(params, 30)
    sort_by = if params["sort_by"] in @sort_columns, do: params["sort_by"], else: "last_used"
    sort_order = if params["sort_order"] in ["asc", "desc"], do: params["sort_order"], else: default_sort_order(sort_by)

    {:noreply,
     socket
     |> assign(
       params: Map.drop(params, ["account_handle", "id"]),
       selected: selected(socket.assigns.selected_account, params["id"], period),
       analytics_preset: preset,
       analytics_period: period,
       search: String.slice(params["search"] || "", 0, 200),
       sort_by: sort_by,
       sort_order: sort_order,
       page: page(params["page"])
     )
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 30_000)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = socket.assigns.params |> Map.put("search", search) |> Map.delete("page")
    {:noreply, push_patch(socket, to: page_path(socket.assigns, params))}
  end

  def handle_event("select_metric", %{"widget" => metric}, socket) when metric in @metrics do
    {:noreply, assign(socket, :metric, metric)}
  end

  def handle_event("select_initialize_percentile", %{"type" => type}, socket) when type in ["avg", "p50", "p90", "p99"] do
    {:noreply, assign(socket, :initialize_percentile, type)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    params =
      socket.assigns.params
      |> Map.drop(["analytics-start-date", "analytics-end-date"])
      |> Map.put("analytics-date-range", preset)

    params =
      if preset == "custom",
        do: Map.merge(params, %{"analytics-start-date" => start_date, "analytics-end-date" => end_date}),
        else: params

    {:noreply, push_patch(socket, to: page_path(socket.assigns, params))}
  end

  defp selected(_account, nil, _period), do: nil

  defp selected(account, id, period) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> DockerCache.repository(account.id, id, period) || raise NotFoundError
      :error -> raise NotFoundError
    end
  end

  defp load(socket) do
    %{selected_account: account, selected: selected, analytics_period: period} = socket.assigns
    volume_id = selected && selected.id

    assign_async(socket, :data, fn ->
      {:ok,
       %{
         data: %{
           repositories: if(is_nil(volume_id), do: DockerCache.repositories(account.id, period), else: []),
           analytics: DockerCache.analytics(account.id, volume_id, period),
           previous: DockerCache.analytics(account.id, volume_id, RunnerVolumesLive.previous_period(period))
         }
       }}
    end)
  end

  def page_path(%{selected_account: account, selected: nil}, params), do: ~p"/#{account.name}/runners/images?#{params}"

  def page_path(%{selected_account: account, selected: selected}, params),
    do: ~p"/#{account.name}/runners/images/#{selected.id}?#{params}"

  # The repositories matching the search, sorted, and whether another page follows.
  def repositories_page(repositories, assigns) do
    search = String.downcase(assigns.search)

    rows =
      repositories
      |> Enum.filter(&String.contains?(String.downcase(&1.repository || ""), search))
      |> Enum.sort_by(&sort_value(&1, assigns.sort_by), sort_direction(assigns.sort_order))

    page = Enum.slice(rows, (assigns.page - 1) * @page_size, @page_size)
    {page, length(rows) > assigns.page * @page_size}
  end

  defp sort_value(repository, "repository"), do: repository.repository
  defp sort_value(repository, "images"), do: repository.image_count
  defp sort_value(repository, "saved_size"), do: repository.saved_bytes || -1
  defp sort_value(repository, "hit_rate"), do: repository.hit_rate || -1

  defp sort_value(repository, "last_used"),
    do: (repository.last_used_at && DateTime.to_unix(repository.last_used_at, :microsecond)) || -1

  defp sort_direction("asc"), do: :asc
  defp sort_direction("desc"), do: :desc

  def sort_options do
    [
      {"repository", dgettext("dashboard_runners", "Repository")},
      {"images", dgettext("dashboard_runners", "Images")},
      {"saved_size", dgettext("dashboard_runners", "Saved size")},
      {"hit_rate", dgettext("dashboard_runners", "Hit rate")},
      {"last_used", dgettext("dashboard_runners", "Last used")}
    ]
  end

  def sort_label(column), do: sort_options() |> List.keyfind(column, 0) |> elem(1)

  def sort_patch(assigns, column) do
    order =
      if assigns.sort_by == column,
        do: if(assigns.sort_order == "asc", do: "desc", else: "asc"),
        else: default_sort_order(column)

    params = assigns.params |> Map.delete("page") |> Map.put("sort_by", column) |> Map.put("sort_order", order)
    page_path(assigns, params)
  end

  defp default_sort_order("repository"), do: "asc"
  defp default_sort_order(_), do: "desc"

  defp page(value) do
    case Integer.parse(value || "1") do
      {n, ""} when n > 0 and n <= 10_000 -> n
      _ -> 1
    end
  end

  attr :id, :string, required: true
  attr :preset, :string, required: true
  attr :period, :any, required: true

  def image_date_picker(assigns) do
    ~H"""
    <.date_picker
      id={@id}
      name="analytics-date-range"
      presets={[
        %{
          id: "last-24-hours",
          label: dgettext("dashboard_runners", "Last 24 hours"),
          period: {24, :hour}
        },
        %{id: "last-7-days", label: dgettext("dashboard_runners", "Last 7 days"), period: {7, :day}},
        %{
          id: "last-30-days",
          label: dgettext("dashboard_runners", "Last 30 days"),
          period: {30, :day}
        },
        %{id: "custom", label: dgettext("dashboard_runners", "Custom")}
      ]}
      selected_preset={@preset}
      period={@period}
      on_period_change="analytics_period_changed"
      min={Date.add(Date.utc_today(), -89)}
      max={Date.utc_today()}
    >
      <:actions>
        <.button
          label={dgettext("dashboard_runners", "Cancel")}
          variant="secondary"
          phx-click={JS.dispatch("phx:date-picker-cancel", detail: %{id: @id})}
        />
        <.button
          label={dgettext("dashboard_runners", "Apply")}
          phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: @id})}
        />
      </:actions>
    </.date_picker>
    """
  end

  attr :id, :string, required: true
  attr :data, :map, required: true
  attr :metric, :string, required: true
  attr :percentile, :string, required: true
  attr :period, :any, required: true

  def analytics_widgets(assigns) do
    ~H"""
    <div data-part="widgets">
      <% hit_rate_change =
        RunnerVolumesLive.hit_rate_trend(
          @data.analytics.activity.hit_rate,
          @data.previous.activity.hit_rate
        ) %>
      <% initialize_change =
        duration_trend(
          RunnersLive.percentile_value(@data.analytics.steps.reused, @percentile),
          RunnersLive.percentile_value(@data.previous.steps.reused, @percentile)
        ) %>
      <% uses_change =
        RunnerVolumesLive.uses_trend(@data.analytics.activity.uses, @data.previous.activity.uses) %>
      <.widget
        id={"#{@id}-hit-rate"}
        legend_color={metric_color("hit_rate")}
        title={dgettext("dashboard_runners", "Hit rate")}
        value={RunnerVolumesLive.percentage(@data.analytics.activity.hit_rate)}
        trend_value={hit_rate_change.value}
        trend_value_label={hit_rate_change.value_label}
        trend_label={hit_rate_change.label}
        trend_type={:regular}
        description={
          dgettext(
            "dashboard_runners",
            "Share of jobs that started from their repository's saved images during the selected period."
          )
        }
        selected={@metric == "hit_rate"}
        phx_click="select_metric"
        phx_value_widget="hit_rate"
      />
      <.percentile_dropdown_widget
        id={"#{@id}-initialize"}
        legend_color={RunnersLive.legend_color_for_percentile(@percentile)}
        title={initialize_title(@percentile)}
        value={duration(RunnersLive.percentile_value(@data.analytics.steps.reused, @percentile))}
        metrics={RunnersLive.percentile_metrics_for(@data.analytics.steps.reused)}
        selected_type={@percentile}
        event_name="select_initialize_percentile"
        trend_value={initialize_change.value}
        trend_value_label={initialize_change.value_label}
        trend_label={initialize_change.label}
        trend_type={:inverse}
        description={
          dgettext(
            "dashboard_runners",
            "Initialize containers step of jobs that started from saved images. For jobs that pulled every layer, the same statistic was %{cold}.",
            cold: duration(RunnersLive.percentile_value(@data.analytics.steps.cold, @percentile))
          )
        }
        selected={@metric == "initialize"}
        phx_click="select_metric"
        phx_value_widget="initialize"
      />
      <.widget
        id={"#{@id}-uses"}
        legend_color={metric_color("uses")}
        title={dgettext("dashboard_runners", "Jobs")}
        value={RunnerVolumesLive.count(@data.analytics.activity.uses)}
        trend_value={uses_change.value}
        trend_value_label={uses_change.value_label}
        trend_label={uses_change.label}
        trend_type={:neutral}
        description={
          dgettext(
            "dashboard_runners",
            "Jobs that started with their repository's image cache during the selected period."
          )
        }
        selected={@metric == "uses"}
        phx_click="select_metric"
        phx_value_widget="uses"
      />
    </div>
    <.card_section data-part="storage-chart-section">
      <.chart
        :if={chart_data?(@data.analytics, @metric)}
        id={"#{@id}-chart"}
        type={if @metric == "uses", do: "bar", else: "line"}
        series={chart_series(@data.analytics, @metric, @percentile)}
        extra_options={chart_options(@metric, @period)}
        y_axis_min={0}
      />
      <.table_empty_state
        :if={!chart_data?(@data.analytics, @metric)}
        title={dgettext("dashboard_runners", "No data in this period")}
      />
    </.card_section>
    """
  end

  def metric_color(metric), do: RunnerVolumesLive.metric_color(metric)

  def chart_data?(analytics, "initialize"), do: not is_nil(analytics.steps.reused.avg)

  def chart_data?(analytics, metric), do: RunnerVolumesLive.detail_chart_data?(analytics, metric)

  def chart_series(analytics, "initialize", percentile) do
    [
      %{
        name: initialize_title(percentile),
        type: "line",
        color: "var:noora-chart-" <> RunnersLive.legend_color_for_percentile(percentile),
        showSymbol: true,
        connectNulls: false,
        data:
          Enum.map(analytics.steps.points, &[DateTime.to_iso8601(&1.at), RunnersLive.percentile_value(&1, percentile)])
      }
    ]
  end

  def chart_series(analytics, metric, _percentile), do: RunnerVolumesLive.detail_chart_series(analytics, metric)

  def initialize_title("p50"), do: dgettext("dashboard_runners", "p50 Initialize containers")
  def initialize_title("p90"), do: dgettext("dashboard_runners", "p90 Initialize containers")
  def initialize_title("p99"), do: dgettext("dashboard_runners", "p99 Initialize containers")
  def initialize_title(_), do: dgettext("dashboard_runners", "Avg. Initialize containers")

  def chart_options("initialize", period) do
    "volumes"
    |> RunnerVolumesLive.storage_chart_options(period)
    |> put_in([:yAxis, :axisLabel, :formatter], "fn:formatMilliseconds")
    |> put_in([:tooltip, :valueFormat], "fn:formatMilliseconds")
  end

  def chart_options(metric, period), do: RunnerVolumesLive.detail_chart_options(metric, period)

  def duration_trend(current, previous) when is_integer(current) and is_integer(previous) and previous > 0,
    do: %{
      value: Float.round((current - previous) / previous * 100, 1),
      value_label: nil,
      label: dgettext("dashboard_runners", "since last period")
    }

  def duration_trend(nil, _previous), do: %{value: 0, value_label: dgettext("dashboard_runners", "No data"), label: ""}

  def duration_trend(_current, _previous),
    do: %{value: 0, value_label: dgettext("dashboard_runners", "No previous data"), label: ""}

  def duration(nil), do: "—"
  def duration(ms), do: DateFormatter.format_duration_from_milliseconds(ms)
end
