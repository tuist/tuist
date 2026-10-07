defmodule TuistOps.JIT.Workers.RevertWorker do
  @moduledoc """
  Reverts a single elevation by flipping `tailscale_jit_elevations`
  to `status="reverted"` and updating the Slack card. The Pomerium
  policy endpoint reads the same row at request time, so the
  revert takes effect on the next kubectl call after this worker
  runs (or earlier — the endpoint also filters by `expires_at`, so
  TTL expiry alone is enough to deny new requests before this
  worker even fires).

  Idempotent on replay: if the row is already `reverted`, this is a
  no-op. Unique on `elevation_id` across the available / scheduled
  / executing / retryable states so a manual revoke insertion races
  cleanly with the TTL-scheduled job (the `replace: [scheduled:
  [:scheduled_at]]` on `Worker.new/2` in `Approvals.revoke/2`
  pulls the scheduled job forward instead of creating a duplicate).

  Runs on the `:tailscale_jit` queue at concurrency 1; the
  concurrency cap is no longer load-bearing now that there's no
  tailnet ACL writer to serialize, but it costs nothing and keeps
  the Slack card update path single-writer.

  GitHub organization admin elevations have no request-time gate to
  fall back on, so for those this worker IS the enforcement: it
  demotes the login back to `member` before flipping the row. A failed
  demote returns an error so Oban retries; once retries are exhausted
  the row is marked `revert_failed` and the Slack card asks for a
  manual demotion.
  """

  use Oban.Worker,
    queue: :revert,
    unique: [
      period: :infinity,
      fields: [:args],
      keys: [:elevation_id],
      # Match Oban's :incomplete preset so a manual revoke insertion
      # races cleanly with the TTL-scheduled job across every state
      # an unfinished job can be in (including :suspended, which
      # newer Oban versions added).
      states: Oban.Job.states() -- [:completed, :discarded, :cancelled]
    ],
    max_attempts: 5

  alias TuistOps.Repo
  alias TuistOps.GitHub.OrgMembership
  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Policy
  alias TuistOps.JIT.Request
  alias TuistOps.JIT.SlackBlocks
  alias TuistOps.JIT.SlackClient

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"elevation_id" => elevation_id}} = job) do
    case Repo.get(Elevation, elevation_id) do
      nil ->
        # Elevation gone; nothing to revert. Treat as success so
        # the job doesn't get stuck retrying.
        :ok

      %Elevation{status: "reverted"} ->
        :ok

      %Elevation{} = elev ->
        if Policy.github_admin_group?(elev.target_group) do
          revert_github(elev, job)
        else
          do_revert(elev)
        end
    end
  end

  defp revert_github(elev, job) do
    case demote_github(elev.github_login) do
      :ok ->
        do_revert(elev)

      {:error, reason} = error ->
        Logger.warning(
          "tuist_ops: github demote failed for elevation_id=#{elev.id} login=#{elev.github_login}: #{inspect(reason)}"
        )

        if job.attempt >= job.max_attempts do
          {:ok, failed} =
            elev
            |> Elevation.transition_changeset(%{
              status: "revert_failed",
              revert_failure_reason: inspect(reason)
            })
            |> Repo.update()

          notify_slack_closed(
            failed,
            "revert failed",
            ":warning: Couldn't demote `#{elev.github_login}`. An organization owner must set their role back to member."
          )
        end

        error
    end
  end

  # Membership is read first because setting a role on a non-member
  # sends an organization invitation. A login that is already a member
  # (demoted by hand) or has left the organization needs nothing.
  defp demote_github(login) do
    case OrgMembership.membership(login) do
      {:ok, %{role: "admin"}} ->
        case OrgMembership.set_role(login, "member") do
          {:ok, %{role: "member"}} -> :ok
          {:ok, membership} -> {:error, {:unexpected_membership, membership}}
          {:error, reason} -> {:error, reason}
        end

      {:ok, _membership} ->
        :ok

      {:error, :not_member} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_revert(elev) do
    {:ok, reverted} =
      elev
      |> Elevation.transition_changeset(%{
        status: "reverted",
        reverted_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
      |> Repo.update()

    notify_slack_closed(reverted, "reverted")
    :ok
  end

  # Updates the original approval card to a terminal state so the
  # Slack thread reflects reality (no more stale "Active until ..."
  # card with a live Revoke button on an already-reverted elevation).
  # Best-effort: a failure here logs but does NOT fail the revert,
  # since the underlying DB transition already succeeded and the
  # gateway will already deny new requests.
  defp notify_slack_closed(%Elevation{request_id: request_id}, label, detail \\ nil) do
    case Repo.get(Request, request_id) do
      %Request{slack_channel_id: channel, slack_message_ts: ts} = req
      when is_binary(channel) and is_binary(ts) ->
        case SlackClient.update_message(channel, ts, SlackBlocks.closed(req, label, detail)) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "tailscale_jit: slack card update failed for request_id=#{request_id}: #{inspect(reason)}"
            )

            :ok
        end

      _ ->
        :ok
    end
  end
end
