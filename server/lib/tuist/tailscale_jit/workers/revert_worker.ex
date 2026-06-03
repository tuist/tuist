defmodule Tuist.TailscaleJIT.Workers.RevertWorker do
  @moduledoc """
  Reverts a single elevation: removes the requester from the
  break-glass Tailscale group and marks the Elevation row
  `reverted`. Idempotent on replay (set semantics on the ACL
  group). Unique on `elevation_id` so a duplicate insertion (e.g.
  from `revoke/2` racing the scheduled job) is a no-op.

  Runs on the `:tailscale_jit` queue at concurrency 1 so the bot
  never has two writers racing the same tailnet ACL.
  """

  use Oban.Worker,
    queue: :tailscale_jit,
    unique: [period: :infinity, fields: [:args], keys: [:elevation_id], states: [:available, :scheduled, :executing, :retryable]],
    max_attempts: 5

  alias Tuist.Repo
  alias Tuist.TailscaleJIT.ACLMutation
  alias Tuist.TailscaleJIT.Elevation
  alias Tuist.TailscaleJIT.TailscaleClient

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"elevation_id" => elevation_id}}) do
    case Repo.get(Elevation, elevation_id) do
      nil ->
        # Elevation gone; nothing to revert. Treat as success so
        # the job doesn't get stuck retrying.
        :ok

      %Elevation{status: "reverted"} ->
        :ok

      %Elevation{} = elev ->
        do_revert(elev)
    end
  end

  defp do_revert(elev) do
    {:ok, elev} =
      elev
      |> Elevation.transition_changeset(%{status: "reverting"})
      |> Repo.update()

    result =
      TailscaleClient.update_acl(fn doc ->
        ACLMutation.remove_member(doc, elev.target_group, elev.requester_email)
      end)

    case result do
      {:ok, _} ->
        elev
        |> Elevation.transition_changeset(%{
          status: "reverted",
          reverted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

        :ok

      {:error, reason} ->
        elev
        |> Elevation.transition_changeset(%{
          status: "revert_failed",
          revert_failure_reason: inspect(reason)
        })
        |> Repo.update()

        Logger.error("tailscale_jit: revert failed for elevation_id=#{elev.id}: #{inspect(reason)}")
        # Raise so Oban retries with backoff.
        {:error, reason}
    end
  end
end
