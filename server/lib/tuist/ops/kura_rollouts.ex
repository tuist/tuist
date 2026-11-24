defmodule Tuist.Ops.KuraRollouts do
  @moduledoc """
  Read-only view of a Kura fleet rollout for Atlas, the counterpart of the
  `/ops/kura/rollouts/:id` page: the rollout's state and pause reason, its
  per-wave progress, the servers still holding a wave open, and its
  recent audit trail.
  """

  alias Tuist.Kura.Rollout
  alias Tuist.Kura.Rollouts

  @server_limit 50
  @event_limit 20

  @doc """
  Reads the rollout with `id`, or without one the active (running or
  paused) rollout, falling back to the latest.
  """
  def get(id) do
    case fetch(id) do
      %Rollout{} = rollout -> {:ok, snapshot(rollout)}
      nil -> {:error, :resource_not_found}
    end
  end

  defp fetch(nil), do: Rollouts.active_rollout() || Rollouts.latest_rollout()
  defp fetch(id), do: Rollouts.get_rollout(id)

  defp snapshot(rollout) do
    {servers, total} = Rollouts.unconverged_servers(rollout, @server_limit)

    %{
      rollout:
        Map.take(rollout, [
          :id,
          :image_tag,
          :baseline_image_tag,
          :status,
          :mode,
          :current_wave,
          :wave_started_at,
          :wave_healthy_since,
          :paused_at,
          :pause_reason,
          :completed_at,
          :inserted_at
        ]),
      waves: Rollouts.wave_summary(rollout),
      unconverged_servers: servers,
      unconverged_server_count: total,
      events:
        rollout
        |> Rollouts.list_events(@event_limit)
        |> Enum.map(&Map.take(&1, [:inserted_at, :action, :actor, :reason, :metadata]))
    }
  end
end
