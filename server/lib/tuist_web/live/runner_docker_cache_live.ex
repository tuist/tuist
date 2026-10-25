defmodule TuistWeb.RunnerDockerCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.DockerCache
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.RunnerVolumesLive

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    if !(Authorization.authorize(:runners_read, user, account) == :ok and FeatureFlags.runners_enabled?(account)) do
      raise NotFoundError
    end

    if connected?(socket), do: Process.send_after(self(), :refresh, 30_000)

    {:ok,
     assign(socket,
       head_title: "#{dgettext("dashboard_runners", "Docker cache")} · #{account.name} · Tuist",
       enabled: FeatureFlags.runner_docker_cache_enabled?(account),
       can_manage: Authorization.authorize(:runners_update, user, account) == :ok
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{preset: preset, period: period} = RunnerVolumesLive.storage_period(params)

    {:noreply,
     socket
     |> assign(
       params: Map.drop(params, ["account_handle", "id"]),
       selected_id: params["id"],
       analytics_preset: preset,
       analytics_period: period
     )
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 30_000)
    {:noreply, load(socket)}
  end

  @impl true
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

  defp load(socket) do
    %{selected_account: account, selected_id: id, analytics_period: period} = socket.assigns

    if id do
      case Ecto.UUID.cast(id) do
        {:ok, id} -> assign(socket, :repository, DockerCache.repository(account.id, id, period) || raise(NotFoundError))
        :error -> raise NotFoundError
      end
    else
      assign_async(socket, :overview, fn -> {:ok, %{overview: DockerCache.overview(account.id, period)}} end)
    end
  end

  def page_path(%{selected_account: account, selected_id: nil}, params),
    do: ~p"/#{account.name}/runners/docker-cache?#{params}"

  def page_path(%{selected_account: account, selected_id: id}, params),
    do: ~p"/#{account.name}/runners/docker-cache/#{id}?#{params}"

  attr :id, :string, required: true
  attr :preset, :string, required: true
  attr :period, :any, required: true

  def docker_date_picker(assigns) do
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
  attr :activity, :map, required: true

  def activity_widgets(assigns) do
    ~H"""
    <.widget
      id={"#{@id}-hit-rate"}
      title={dgettext("dashboard_runners", "Reuse rate")}
      value={RunnerVolumesLive.percentage(@activity.hit_rate)}
      empty={is_nil(@activity.hit_rate)}
      empty_label={dgettext("dashboard_runners", "No jobs yet")}
      description={
        dgettext(
          "dashboard_runners",
          "Share of jobs that started from their repository's saved images during the selected period."
        )
      }
    />
    <.widget
      id={"#{@id}-reused"}
      title={dgettext("dashboard_runners", "Initialize containers, reused")}
      value={duration(@activity.hit_step_ms)}
      empty={is_nil(@activity.hit_step_ms)}
      empty_label={dgettext("dashboard_runners", "No reused jobs yet")}
      description={
        dgettext(
          "dashboard_runners",
          "Median duration of the Initialize containers step for jobs that started from saved images."
        )
      }
    />
    <.widget
      id={"#{@id}-cold"}
      title={dgettext("dashboard_runners", "Initialize containers, cold")}
      value={duration(@activity.miss_step_ms)}
      empty={is_nil(@activity.miss_step_ms)}
      empty_label={dgettext("dashboard_runners", "No cold jobs")}
      description={
        dgettext(
          "dashboard_runners",
          "Median duration of the Initialize containers step for jobs that pulled every layer."
        )
      }
    />
    """
  end

  def duration(nil), do: "—"
  def duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)} s"
  def duration(ms), do: "#{div(ms, 60_000)} min #{rem(div(ms, 1000), 60)} s"

  def status_label(:ready), do: dgettext("dashboard_runners", "Saved")
  def status_label(:waiting), do: dgettext("dashboard_runners", "Waiting for a save")
  def status_label(:cleared), do: dgettext("dashboard_runners", "Cleared")

  def status_color(:ready), do: "success"
  def status_color(:waiting), do: "information"
  def status_color(:cleared), do: "neutral"

  def count(value), do: TuistWeb.CldrHelpers.format_number(value || 0)
end
