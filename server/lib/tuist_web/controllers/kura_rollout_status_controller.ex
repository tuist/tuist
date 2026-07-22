defmodule TuistWeb.KuraRolloutStatusController do
  @moduledoc """
  Minimal unauthenticated status surface for the deploy pipeline's Kura
  promotion gate (spec #79): production promotion waits for the canary
  environment's rollout of the target tag to complete, and fails when it
  is paused, aborted, or superseded.

  Discloses only the rollout's tag and lifecycle state — no fleet,
  account, or health detail — the same sensitivity class as `/ready`.
  """
  use TuistWeb, :controller

  alias Tuist.FeatureFlags
  alias Tuist.Kura.Rollouts

  def show(conn, %{"image_tag" => image_tag}) when is_binary(image_tag) do
    if FeatureFlags.kura_rollout_orchestration_enabled?() do
      json(conn, %{enabled: true, rollout: rollout_payload(image_tag)})
    else
      json(conn, %{enabled: false, rollout: nil})
    end
  end

  def show(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "image_tag is required"})
  end

  defp rollout_payload(image_tag) do
    case Rollouts.latest_rollout_for_tag(image_tag) do
      nil ->
        nil

      rollout ->
        %{
          image_tag: rollout.image_tag,
          status: rollout.status,
          mode: rollout.mode,
          current_wave: rollout.current_wave
        }
    end
  end
end
