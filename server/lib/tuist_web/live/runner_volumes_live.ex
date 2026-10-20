defmodule TuistWeb.RunnerVolumesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.Profile
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker

  @volume_name_max_length 48

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    if !(Authorization.authorize(:runners_read, user, account) == :ok and FeatureFlags.runners_enabled?(account)) do
      raise NotFoundError
    end

    if connected?(socket), do: Process.send_after(self(), :refresh, 15_000)

    {:ok,
     assign(socket,
       head_title: "#{dgettext("dashboard_runners", "Volumes")} · #{account.name} · Tuist",
       can_manage: Authorization.authorize(:runners_update, user, account) == :ok,
       include_builtin: FeatureFlags.runner_opt_in_caches_enabled?(account),
       pending_action: nil,
       selected: nil,
       selected_tab: "overview",
       storage_metric: "used_bytes",
       detail_metric: "used_bytes",
       search: "",
       page: 1
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected =
      if params["id"] do
        CacheVolumes.get(socket.assigns.selected_account.id, params["id"]) || raise NotFoundError
      end

    if selected && selected.builtin_name && !socket.assigns.include_builtin, do: raise(NotFoundError)

    %{preset: preset, period: period} = storage_period(params)

    sort_by =
      if params["sort_by"] in ["volume", "repository", "used_space", "capacity", "last_used"],
        do: params["sort_by"],
        else: "last_used"

    sort_order = if params["sort_order"] in ["asc", "desc"], do: params["sort_order"], else: default_sort_order(sort_by)

    {:noreply,
     socket
     |> assign(
       params: Map.drop(params, ["account_handle", "id"]),
       profile_names: CacheVolumes.default_profile_names(socket.assigns.selected_account.id, List.wrap(selected)),
       analytics_preset: preset,
       analytics_period: period,
       selected: selected,
       selected_tab: selected_tab(params["tab"]),
       search: String.slice(params["search"] || "", 0, 200),
       sort_by: sort_by,
       sort_order: sort_order,
       page: page(params["page"])
     )
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 15_000)
    %{preset: preset, period: period} = storage_period(socket.assigns.params)
    {:noreply, socket |> assign(analytics_preset: preset, analytics_period: period) |> load()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = socket.assigns.params |> Map.put("search", search) |> Map.delete("page")
    {:noreply, push_patch(socket, to: ~p"/#{socket.assigns.selected_account.name}/runners/volumes?#{params}")}
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

    path =
      if socket.assigns[:selected],
        do: ~p"/#{socket.assigns.selected_account.name}/runners/volumes/#{socket.assigns.selected.id}?#{params}",
        else: ~p"/#{socket.assigns.selected_account.name}/runners/volumes?#{params}"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("select_storage_metric", %{"widget" => metric}, socket)
      when metric in ["volumes", "used_bytes", "hit_rate"] do
    {:noreply, assign(socket, :storage_metric, metric)}
  end

  def handle_event("select_detail_metric", %{"widget" => metric}, socket)
      when metric in ["used_bytes", "hit_rate", "uses"] do
    {:noreply, assign(socket, :detail_metric, metric)}
  end

  def handle_event("request_delete", %{"id" => id}, socket), do: request_action(socket, id, :delete)

  def handle_event("cancel", _, %{assigns: %{pending_action: nil}} = socket), do: {:noreply, socket}

  def handle_event("cancel", _, socket) do
    {action, _} = socket.assigns.pending_action
    {:noreply, socket |> assign(:pending_action, nil) |> push_event("close-modal", %{id: "volume-confirm-#{action}"})}
  end

  def handle_event("confirm", _, socket) do
    account = socket.assigns.selected_account

    with :ok <- Authorization.authorize(:runners_update, socket.assigns.current_user, account),
         {:delete, id} <- socket.assigns.pending_action,
         volume when not is_nil(volume) <- CacheVolumes.get(account.id, id) do
      case CacheVolumes.delete(account.id, volume.id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:pending_action, nil)
           |> push_event("close-modal", %{id: "volume-confirm-delete"})
           |> put_flash(
             :info,
             dgettext("dashboard_runners", "Volume cleared. Running jobs can finish.")
           )
           |> load()}

        _ ->
          {:noreply, put_flash(socket, :error, dgettext("dashboard_runners", "Could not update volume. Please retry."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp request_action(socket, id, action) do
    volume = CacheVolumes.get(socket.assigns.selected_account.id, id)

    if (socket.assigns.can_manage and volume) && is_nil(volume.builtin_name) do
      {:noreply,
       socket |> assign(:pending_action, {action, id}) |> push_event("open-modal", %{id: "volume-confirm-#{action}"})}
    else
      {:noreply, socket}
    end
  end

  defp load(socket) do
    %{selected_account: account, search: search, page: page, selected: selected, selected_tab: tab} =
      socket.assigns

    period = socket.assigns.analytics_period
    builtin = [include_builtin: socket.assigns.include_builtin]
    sort_options = [sort_by: socket.assigns.sort_by, sort_order: socket.assigns.sort_order] ++ builtin

    assign_async(socket, :data, fn ->
      data =
        if selected do
          volume = CacheVolumes.get(account.id, selected.id)

          %{
            volumes: List.wrap(volume),
            more?: false,
            stats: CacheVolumes.statistics([selected.id]),
            profile_names: CacheVolumes.default_profile_names(account.id, List.wrap(volume)),
            history:
              case tab do
                "overview" -> CacheVolumes.history(account.id, selected.id, 1, 5)
                "jobs" -> CacheVolumes.history(account.id, selected.id, page)
                _ -> []
              end,
            analytics:
              if tab == "overview" do
                %{
                  storage: CacheVolumes.storage_history(account.id, period, selected.id),
                  activity: CacheVolumes.usage_analytics(account.id, selected.id, period),
                  previous_activity: CacheVolumes.usage_analytics(account.id, selected.id, previous_period(period))
                }
              end
          }
        else
          account.id
          |> CacheVolumes.list(search, page, sort_options)
          |> then(&Map.put(&1, :profile_names, CacheVolumes.default_profile_names(account.id, &1.volumes)))
          |> Map.put(:history, [])
          |> Map.put(:activity, CacheVolumes.usage_analytics(account.id, nil, period, builtin))
          |> Map.put(:previous_activity, CacheVolumes.usage_analytics(account.id, nil, previous_period(period), builtin))
          |> Map.put(:storage_history, CacheVolumes.storage_history(account.id, period, nil, builtin))
        end

      {:ok, %{data: data}}
    end)
  end

  def sort_options do
    [
      {"volume", dgettext("dashboard_runners", "Volume")},
      {"repository", dgettext("dashboard_runners", "Repository")},
      {"used_space", dgettext("dashboard_runners", "Used space")},
      {"capacity", dgettext("dashboard_runners", "Capacity")},
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
    ~p"/#{assigns.selected_account.name}/runners/volumes?#{params}"
  end

  defp default_sort_order(column) when column in ["volume", "repository"], do: "asc"
  defp default_sort_order(_), do: "desc"

  attr :id, :string, required: true
  attr :preset, :string, required: true
  attr :period, :any, required: true

  defp volume_date_picker(assigns) do
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
        %{
          id: "last-7-days",
          label: dgettext("dashboard_runners", "Last 7 days"),
          period: {7, :day}
        },
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
          phx-click={
            JS.dispatch("phx:date-picker-cancel",
              detail: %{id: @id}
            )
          }
        />
        <.button
          label={dgettext("dashboard_runners", "Apply")}
          phx-click={
            JS.dispatch("phx:date-picker-apply",
              detail: %{id: @id}
            )
          }
        />
      </:actions>
    </.date_picker>
    """
  end

  def tab_params(params, tab), do: params |> Map.drop(["page", "size_page"]) |> Map.put("tab", tab)

  def percentage(nil), do: "—"
  def percentage(value), do: "#{value}%"

  def previous_period({start, finish}) do
    duration = DateTime.diff(finish, start, :microsecond)
    {DateTime.add(start, -duration, :microsecond), DateTime.add(start, -1, :microsecond)}
  end

  def hit_rate_trend(current, previous) when is_number(current) and is_number(previous) do
    %{
      value: if(previous == 0, do: 0.0, else: Float.round(current / previous * 100 - 100, 1)),
      value_label: nil,
      label: dgettext("dashboard_runners", "since last period")
    }
  end

  def hit_rate_trend(nil, _previous), do: %{value: 0, value_label: dgettext("dashboard_runners", "No data"), label: ""}

  def hit_rate_trend(_current, nil),
    do: %{value: 0, value_label: dgettext("dashboard_runners", "No previous data"), label: ""}

  def uses_trend(current, previous) when is_integer(current) and is_integer(previous) do
    label = dgettext("dashboard_runners", "since last period")

    cond do
      previous == 0 and current != 0 -> %{value: current, value_label: "+" <> count(current), label: label}
      previous == 0 -> %{value: 0, value_label: nil, label: label}
      true -> %{value: (current - previous) / previous * 100, value_label: nil, label: label}
    end
  end

  def uses_trend(_current, _previous),
    do: %{value: 0, value_label: nil, label: dgettext("dashboard_runners", "since last period")}

  def inventory_chart_data?(data, "hit_rate"), do: not is_nil(data.activity.hit_rate)
  def inventory_chart_data?(data, _metric), do: data.storage_history != []

  def inventory_chart_series(data, "hit_rate"), do: detail_chart_series(data, "hit_rate")
  def inventory_chart_series(data, metric), do: storage_chart_series(data.storage_history, metric)

  def detail_chart_data?(analytics, "used_bytes"), do: analytics.storage != []

  def detail_chart_data?(analytics, "hit_rate"), do: not is_nil(analytics.activity.hit_rate)
  def detail_chart_data?(_analytics, "uses"), do: true

  def detail_chart_series(analytics, "used_bytes"), do: storage_chart_series(analytics.storage, "used_bytes")

  def detail_chart_series(analytics, metric) do
    {field, label} =
      if metric == "uses",
        do: {:uses, dgettext("dashboard_runners", "Job runs")},
        else: {:hit_rate, dgettext("dashboard_runners", "Hit rate")}

    [
      %{
        name: label,
        type: if(metric == "uses", do: "bar", else: "line"),
        color: "var:noora-chart-" <> metric_color(metric),
        showSymbol: true,
        connectNulls: false,
        data: Enum.map(analytics.activity.points, &[DateTime.to_iso8601(&1.at), Map.fetch!(&1, field)])
      }
    ]
  end

  def detail_chart_options("hit_rate", period) do
    options = storage_chart_options("volumes", period)

    options
    |> put_in([:yAxis, :max], 100)
    |> put_in([:yAxis, :axisLabel, :formatter], "{value}%")
    |> put_in([:tooltip, :valueFormat], "{value}%")
  end

  def detail_chart_options("uses", period), do: storage_chart_options("volumes", period)
  def detail_chart_options(metric, period), do: storage_chart_options(metric, period)

  def selected_tab("jobs"), do: "jobs"
  def selected_tab(_), do: "overview"

  defp page(value) do
    case Integer.parse(value || "1") do
      {n, ""} when n > 0 and n <= 10_000 -> n
      _ -> 1
    end
  end

  def stats(data, volume), do: Map.get(data.stats, volume.id, %{})

  # A saved snapshot is nearly full against the capacity the next job gets, so
  # a larger requested size clears the warning.
  def full_snapshot?(%{builtin_name: nil, head_id: head_id} = volume, stats) when not is_nil(head_id),
    do: CacheVolumes.full?(stats[:saved_bytes], next_volume_bytes(volume, stats))

  def full_snapshot?(_volume, _stats), do: false

  def full_snapshot_description(volume, stats) do
    dgettext(
      "dashboard_runners",
      "The saved snapshot uses %{used} of %{capacity}. If a job runs out of space on it, the next job starts from an empty volume and saves a new snapshot.",
      used: bytes(stats[:saved_bytes]),
      capacity: bytes(next_volume_bytes(volume, stats))
    )
  end

  defp next_volume_bytes(volume, stats), do: CacheVolumes.next_volume_bytes(volume, stats[:head_volume_bytes])

  def volume_capacity(volume, stats), do: CacheVolumes.volume_bytes(volume, stats[:head_volume_bytes])

  def pending_volume_bytes(volume, stats), do: CacheVolumes.pending_volume_bytes(volume, stats[:head_volume_bytes])

  def pending_size_description(volume, stats) do
    dgettext(
      "dashboard_runners",
      "Saved at %{capacity}. New contents will use %{pending} after the next clear.",
      capacity: bytes(volume_capacity(volume, stats)),
      pending: bytes(pending_volume_bytes(volume, stats))
    )
  end

  # Managed caches show what they hold rather than their storage key; the
  # Xcode and module caches share the built-in volume. Default volumes show
  # the runner profile they belong to.
  def display_name(volume, profile_names \\ %{})

  def display_name(%{builtin_name: name}, _profile_names) when is_binary(name),
    do: dgettext("dashboard_runners", "Xcode and module caches")

  def display_name(%{key: "tuist-xcode"}, _profile_names), do: dgettext("dashboard_runners", "Xcode cache")
  def display_name(%{key: "tuist-module"}, _profile_names), do: dgettext("dashboard_runners", "Module cache")
  def display_name(%{key: "tuist-gradle"}, _profile_names), do: dgettext("dashboard_runners", "Gradle cache")

  def display_name(%{key: key} = volume, profile_names) do
    cond do
      name = Map.get(profile_names, volume.id) ->
        dgettext("dashboard_runners", "Default (%{profile})", profile: Profile.dispatch_label(%Profile{name: name}))

      CacheVolumes.default_volume?(volume) ->
        dgettext("dashboard_runners", "Default")

      true ->
        key
    end
  end

  def volume_name(volume, profile_names \\ %{}) do
    name = display_name(volume, profile_names)

    if String.length(name) > @volume_name_max_length,
      do: String.slice(name, 0, @volume_name_max_length - 1) <> "…",
      else: name
  end

  def bytes(nil), do: "—"
  def bytes(%Decimal{} = value), do: value |> Decimal.to_integer() |> bytes()
  def bytes(value), do: ByteFormatter.format_bytes(value)

  def storage_bytes(%{retained_copies: 0}, _field), do: bytes(0)
  def storage_bytes(stats, field), do: bytes(stats[field])

  def storage_capacity(_volume, %{retained_copies: 0}), do: bytes(0)
  def storage_capacity(_volume, %{retained_capacity_bytes: capacity}) when not is_nil(capacity), do: bytes(capacity)

  def storage_capacity(volume, stats) do
    case volume_capacity(volume, stats) do
      nil -> dgettext("dashboard_runners", "Not reported")
      capacity -> bytes(capacity)
    end
  end

  # A custom volume's capacity is what its jobs get; the built-in volume reports
  # its measured copies.
  def detail_capacity(%{builtin_name: nil} = volume, stats), do: bytes(volume_capacity(volume, stats))
  def detail_capacity(volume, stats), do: storage_capacity(volume, stats)

  def used_space(%{head_id: nil, deleted_at: nil}, %{retained_bytes: nil}), do: bytes(0)
  def used_space(%{head_id: nil, deleted_at: nil}, stats) when map_size(stats) == 0, do: bytes(0)
  def used_space(_volume, stats), do: storage_bytes(stats, :retained_bytes)

  def measurement_coverage(0), do: nil
  def measurement_coverage(nil), do: nil

  def measurement_coverage(count) do
    dngettext("dashboard_runners", "%{count} copy unmeasured", "%{count} copies unmeasured", count)
  end

  def metric_color("volumes"), do: "primary"
  def metric_color("used_bytes"), do: "secondary"
  def metric_color("hit_rate"), do: "tertiary"
  def metric_color("uses"), do: "p50"

  def storage_chart_series(points, metric \\ nil) do
    for {field, label, color} <- [
          {:volumes, dgettext("dashboard_runners", "Volumes"), "var:noora-chart-" <> metric_color("volumes")},
          {:used_bytes, dgettext("dashboard_runners", "Used space"), "var:noora-chart-" <> metric_color("used_bytes")},
          {:capacity_bytes, dgettext("dashboard_runners", "Capacity"), "var:noora-chart-quaternary"}
        ],
        is_nil(metric) or Atom.to_string(field) == metric do
      %{
        name: label,
        type: "line",
        color: color,
        smooth: 0.1,
        showSymbol: length(points) == 1,
        connectNulls: false,
        data: Enum.map(points, &[DateTime.to_iso8601(&1.at), Map.fetch!(&1, field)])
      }
    end
  end

  def storage_chart_options(metric, period \\ nil) do
    formatter = if metric == "volumes", do: "fn:formatNumber", else: "fn:formatBytes"

    bounds =
      if period, do: %{min: DateTime.to_iso8601(elem(period, 0)), max: DateTime.to_iso8601(elem(period, 1))}, else: %{}

    %{
      grid: %{left: 12, right: 24, top: 20, bottom: 4, containLabel: true},
      xAxis:
        Map.merge(
          %{
            type: "time",
            boundaryGap: false,
            axisLabel: %{
              color: "var:noora-surface-label-secondary",
              formatter: "fn:toLocaleDate",
              hideOverlap: true
            }
          },
          bounds
        ),
      yAxis: %{
        min: 0,
        splitNumber: 4,
        minInterval: if(metric == "volumes", do: 1, else: 0),
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
      },
      tooltip: %{valueFormat: formatter, dateFormat: "hour"},
      legend: %{show: false}
    }
  end

  def storage_period(params) do
    params =
      if params["analytics-date-range"] in ["last-24-hours", "last-7-days", "last-30-days", "custom"],
        do: params,
        else: Map.delete(params, "analytics-date-range")

    selection = DatePicker.date_picker_params(params, "analytics", default_preset: "last-7-days", default_days: 7)
    {start, finish} = selection.period
    now = DateTime.truncate(DateTime.utc_now(), :second)
    earliest = DateTime.add(now, -90, :day)
    finish = if DateTime.after?(finish, now), do: now, else: finish

    if DateTime.before?(start, finish) and not DateTime.before?(start, earliest) and not DateTime.after?(finish, now) do
      %{selection | period: {start, finish}}
    else
      DatePicker.date_picker_params(%{}, "analytics", default_preset: "last-7-days", default_days: 7)
    end
  end

  def storage_value(points, metric) do
    case List.last(points) do
      nil -> "—"
      point when metric == :volumes -> count(point.volumes)
      point -> bytes(Map.fetch!(point, metric))
    end
  end

  def storage_trend(points, metric, {start, finish}) do
    first = List.first(points)
    last = List.last(points)
    label = dgettext("dashboard_runners", "since last period")

    if storage_boundary?(first, metric, start) and storage_boundary?(last, metric, finish) do
      previous = Map.fetch!(first, metric)
      change = Map.fetch!(last, metric) - previous

      if previous == 0 and change != 0 do
        value_label = "+" <> if(metric == :volumes, do: count(change), else: bytes(change))
        %{value: change, value_label: value_label, label: label}
      else
        %{value: if(previous == 0, do: 0, else: change / previous * 100), value_label: nil, label: label}
      end
    else
      %{value: 0, value_label: nil, label: label}
    end
  end

  defp storage_boundary?(nil, _metric, _at), do: false

  defp storage_boundary?(point, metric, at) do
    DateTime.compare(point.at, at) == :eq and not is_nil(point[metric])
  end

  def relative_time(nil), do: "—"
  def relative_time(value), do: DateFormatter.from_now(value)

  def status_color(%{deleted_at: deleted_at}, _) when not is_nil(deleted_at), do: "neutral"
  def status_color(%{head_id: head_id}, _) when not is_nil(head_id), do: "success"
  def status_color(_, _), do: "neutral"

  def job_label(%{job_name: name}) when is_binary(name) and name != "", do: name
  def job_label(usage), do: "# #{usage.workflow_job_id}"

  def workflow_label(%{workflow_name: name}) when is_binary(name) and name != "", do: name
  def workflow_label(_), do: dgettext("dashboard_runners", "Unknown")

  def storage_description(stats, field) do
    description =
      dgettext(
        "dashboard_runners",
        "Summed across saved snapshots and job copies, including copies awaiting deletion. Shared data may be counted more than once; these are not unique physical bytes or a billing amount."
      )

    case measurement_coverage(stats[field]) do
      nil -> description
      coverage -> description <> " " <> coverage <> "."
    end
  end

  def time(nil), do: "—"
  def time(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  def count(value), do: TuistWeb.CldrHelpers.format_number(value || 0)
  def hit_rate(%{uses: uses, hits: hits}) when uses > 0, do: "#{Float.round(100 * hits / uses, 1)}%"
  def hit_rate(_), do: "—"
  def latency(%Decimal{} = value), do: "#{value |> Decimal.to_float() |> Float.round(0)} ms"
  def latency(_), do: "—"

  def status(volume, stats) do
    cond do
      volume.deleted_at && Map.get(stats, :retained_copies, 0) > 0 -> dgettext("dashboard_runners", "Deletion pending")
      volume.deleted_at -> dgettext("dashboard_runners", "Deleted")
      volume.head_id -> dgettext("dashboard_runners", "Ready")
      true -> dgettext("dashboard_runners", "Empty")
    end
  end
end
