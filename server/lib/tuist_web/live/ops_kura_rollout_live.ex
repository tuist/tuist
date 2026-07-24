defmodule TuistWeb.OpsKuraRolloutLive do
  @moduledoc """
  Internal ops view for Kura runtime rollouts (spec #79): the active
  rollout with its wave progress, the operator verbs (pause, resume,
  expedite, abort) next to it, the audit trail, and recent rollout
  history — so the person paged during an incident acts from the same
  screen that explains the situation.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.FeatureFlags
  alias Tuist.Kura.Rollouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Rollouts.subscribe()
    end

    {:ok,
     socket
     |> assign(:head_title, "Kura Rollouts · Tuist")
     |> load_rollout_state()}
  end

  @impl true
  def handle_info({:kura_rollouts, :updated}, socket) do
    {:noreply, load_rollout_state(socket)}
  end

  @impl true
  def handle_event("operate", %{"action" => action, "reason" => reason}, socket) do
    actor = socket.assigns.current_user.email
    rollout = socket.assigns.rollout

    result =
      case action do
        "pause" -> Rollouts.pause(rollout, actor, reason)
        "resume" -> Rollouts.resume(rollout, actor, reason)
        "expedite" -> Rollouts.expedite(rollout, actor, reason)
        "abort" -> Rollouts.abort(rollout, actor, reason)
        _ -> {:error, :unknown_action}
      end

    socket =
      case result do
        {:ok, _rollout} ->
          put_flash(socket, :info, "Rollout #{action} applied.")

        {:error, reason} ->
          put_flash(socket, :error, "Could not #{action} the rollout: #{inspect(reason)}")
      end

    {:noreply, load_rollout_state(socket)}
  end

  defp load_rollout_state(socket) do
    rollout = Rollouts.latest_rollout()

    socket
    |> assign(:orchestration_enabled, FeatureFlags.kura_rollout_orchestration_enabled?())
    |> assign(:rollout, rollout)
    |> assign(:waves, (rollout && Rollouts.wave_summary(rollout)) || [])
    |> assign(:events, (rollout && Rollouts.list_events(rollout)) || [])
    |> assign(:rollouts, Rollouts.list_rollouts(10))
  end

  def format_metadata(metadata) when metadata == %{}, do: ""

  def format_metadata(metadata) do
    Enum.map_join(metadata, ", ", fn {key, value} -> "#{key}: #{value}" end)
  end
end
