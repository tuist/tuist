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
    unique: [
      period: :infinity,
      fields: [:args],
      keys: [:elevation_id],
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 5

  alias Tuist.Repo
  alias Tuist.TailscaleJIT.ACLMutation
  alias Tuist.TailscaleJIT.Elevation
  alias Tuist.TailscaleJIT.Request
  alias Tuist.TailscaleJIT.SlackBlocks
  alias Tuist.TailscaleJIT.SlackClient
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
        {:ok, reverted} =
          elev
          |> Elevation.transition_changeset(%{
            status: "reverted",
            reverted_at: DateTime.truncate(DateTime.utc_now(), :second)
          })
          |> Repo.update()

        notify_slack_closed(reverted, "reverted")
        :ok

      {:error, reason} ->
        {:ok, failed} =
          elev
          |> Elevation.transition_changeset(%{
            status: "revert_failed",
            revert_failure_reason: inspect(reason)
          })
          |> Repo.update()

        notify_slack_closed(failed, "revert failed", "Reason: #{inspect(reason)}")
        Logger.error("tailscale_jit: revert failed for elevation_id=#{elev.id}: #{inspect(reason)}")
        # Raise so Oban retries with backoff.
        {:error, reason}
    end
  end

  # Updates the original approval card to a terminal state so the
  # Slack thread reflects reality (no more stale "Active until ..."
  # card with a live Revoke button on an already-reverted elevation).
  # Best-effort: a failure here logs but does NOT fail the revert,
  # since the underlying ACL mutation already succeeded.
  defp notify_slack_closed(%Elevation{request_id: request_id}, label, detail \\ nil) do
    case Repo.get(Request, request_id) do
      %Request{slack_channel_id: channel, slack_message_ts: ts} = req
      when is_binary(channel) and is_binary(ts) ->
        case SlackClient.update_message(channel, ts, SlackBlocks.closed(req, label, detail)) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("tailscale_jit: slack card update failed for request_id=#{request_id}: #{inspect(reason)}")
            :ok
        end

      _ ->
        :ok
    end
  end
end
