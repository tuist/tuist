defmodule Atlas.MCP.Tools.GetTuistKuraRollout do
  @moduledoc "Reads a Tuist Kura fleet rollout, as the server's /ops/kura/rollouts page shows it."

  use Atlas.MCP.Tool,
    name: "get_tuist_kura_rollout",
    schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{
          "type" => "string",
          "format" => "uuid",
          "description" =>
            "Rollout UUID. Omit for the active (running or paused) rollout, or the latest one when none is active."
        }
      }
    },
    # The inner records are owned by the Tuist server's internal
    # /kura/rollout endpoint (see Atlas.TuistServer.get_kura_rollout/2), so
    # only the top-level envelope is modeled here.
    output_schema: %{
      "type" => "object",
      "additionalProperties" => true,
      "required" => ["rollout", "waves", "unconverged_servers", "unconverged_server_count", "events"],
      "properties" => %{
        "rollout" => %{"type" => "object"},
        "waves" => %{"type" => "array", "items" => %{"type" => "object"}},
        "unconverged_servers" => %{"type" => "array", "items" => %{"type" => "object"}},
        "unconverged_server_count" => %{"type" => "integer"},
        "events" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    }

  alias Atlas.MCP.Tools.TuistPostgres
  alias Atlas.TuistServer

  @impl EMCP.Tool
  def description do
    "Read a Kura fleet rollout in the Tuist server (production), the data behind /ops/kura/rollouts: target and baseline " <>
      "image tags, status (running, paused, completed, aborted, superseded), mode, current wave, when that wave started, " <>
      "and the pause reason and time. A wave that does not converge within one hour pauses with wave_deadline_exceeded. " <>
      "Also returns per-wave account, server, converged, soak-eligible and held counts; up to 50 servers that have not " <>
      "converged on the target (account handle, region, status, observed image tag, last observation and readiness, and " <>
      "their rollout deployment); and the 20 newest audit events. Read-only: resuming or aborting stays on the ops page."
  end

  def execute(_conn, args) do
    with :ok <- TuistPostgres.ensure_available(),
         {:ok, id} <- rollout_id(args) do
      TuistServer.get_kura_rollout(id)
    end
  end

  defp rollout_id(%{"id" => id}) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, "id must be a rollout UUID."}
    end
  end

  defp rollout_id(%{"id" => nil}), do: {:ok, nil}
  defp rollout_id(%{"id" => _id}), do: {:error, "id must be a rollout UUID."}
  defp rollout_id(_args), do: {:ok, nil}
end
