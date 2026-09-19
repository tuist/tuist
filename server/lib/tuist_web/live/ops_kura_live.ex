defmodule TuistWeb.OpsKuraLive do
  @moduledoc """
  Internal ops overview for Kura runtime rollouts (spec #79): the latest
  rollout with its wave progress and operator verbs, plus the most
  recent audit events and rollout history. Full, paginated sets live on
  the dedicated history and detail pages so this overview stays readable
  as rollouts accumulate.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.OpsKuraComponents

  alias Tuist.FeatureFlags
  alias Tuist.Kura.Rollouts

  @recent_limit 10

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
  # Tolerant of a submit that arrives without one of the fields: the form
  # marks both required, but a missing key must not take the LiveView down
  # with a FunctionClauseError. `operate/4` rejects an empty action, and a
  # nil rollout (a fresh environment has none) is rejected there too.
  def handle_event("operate", params, socket) do
    action = Map.get(params, "action", "")
    reason = Map.get(params, "reason", "")
    actor = socket.assigns.current_user.email

    socket =
      case operate(socket.assigns.rollout, action, actor, reason) do
        {:ok, _rollout} ->
          put_flash(socket, :info, "Rollout #{action} applied.")

        {:error, reason} ->
          put_flash(socket, :error, operate_error_message(reason, action))
      end

    {:noreply, load_rollout_state(socket)}
  end

  defp load_rollout_state(socket) do
    rollout = Rollouts.latest_rollout()

    socket
    |> assign(:orchestration_enabled, FeatureFlags.kura_rollout_orchestration_enabled?())
    |> assign(:rollout, rollout)
    |> assign(:waves, (rollout && Rollouts.wave_summary(rollout)) || [])
    |> assign(:rollouts, Rollouts.list_rollouts(@recent_limit))
    |> assign(:rollouts_total, Rollouts.count_rollouts())
  end
end
