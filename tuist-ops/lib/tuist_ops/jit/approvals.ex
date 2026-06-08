defmodule TuistOps.JIT.Approvals do
  @moduledoc """
  Public API for the JIT elevation bot. Four operations:

    * `request_elevation/1` — create a Request, post the Slack card,
      return the persisted Request.
    * `approve/2` — second human says yes. Gates self-approve via
      `Policy.self_approval_allowed?/2` and the second-human path
      via `Policy.approver_allowed?/2`, then creates an Elevation
      row (status=active with TTL) and schedules a revert.
    * `deny/2` — second human says no. Updates Slack, no elevation
      row created.
    * `revoke/2` — early revert. Pulls the scheduled RevertWorker
      job forward to fire now.

  Elevation is a Postgres-side flag, not a tailnet ACL mutation.
  The Pomerium gateway's ext_authz endpoint reads
  `tailscale_jit_elevations` at request time to decide whether to
  inject the elevated impersonation header on a given kubectl call.
  No tailnet policy is written from this module; revocation is just
  a DB status update.
  """

  alias TuistOps.Repo
  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Policy
  alias TuistOps.JIT.Request
  alias TuistOps.JIT.SlackBlocks
  alias TuistOps.JIT.SlackClient
  alias TuistOps.JIT.Workers.RevertWorker

  require Logger

  # 10 minutes for a second human to click Approve. Independent of
  # the elevation TTL, which is the runtime grant length.
  @approval_window_seconds 600
  # Default and max elevation TTLs. Tight bounds are deliberate:
  # shorter sessions mean fresh attestation of intent.
  @default_ttl_seconds 15 * 60
  @max_ttl_seconds 60 * 60

  @doc """
  Creates a new request and posts the Slack approval card. `attrs`
  must include `:requester_email`, `:requester_slack_id`,
  `:target_group`, `:intent`, `:slack_channel_id`, and may include
  `:ttl_seconds` (default #{div(@default_ttl_seconds, 60)} min,
  capped at #{div(@max_ttl_seconds, 60)} min).
  """
  def request_elevation(attrs) when is_map(attrs) do
    ttl = attrs |> Map.get(:ttl_seconds, @default_ttl_seconds) |> clamp_ttl()
    expires_at = DateTime.add(DateTime.utc_now(), @approval_window_seconds, :second)

    changeset =
      attrs
      |> Map.put(:ttl_seconds, ttl)
      |> Map.put(:expires_at, expires_at)
      |> Request.create_changeset()

    with {:ok, request} <- Repo.insert(changeset),
         self_approval =
           Policy.self_approval_allowed?(request.requester_email, request.target_group),
         {:ok, ts} <-
           SlackClient.post_message(
             request.slack_channel_id,
             SlackBlocks.pending(request, self_approval_allowed?: self_approval)
           ) do
      request
      |> Request.transition_changeset(%{slack_message_ts: ts})
      |> Repo.update()
    else
      {:error, reason} ->
        Logger.warning("tailscale_jit: request_elevation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Approves a request. `actor` is the Slack user who clicked
  Approve; the function rejects the call (without any state
  transition) when `actor.slack_id == request.requester_slack_id`.

  Idempotent on replay: if the request is already approved, the
  existing Elevation is returned.
  """
  def approve(request_id, %{slack_id: actor_slack_id, email: actor_email}) do
    fn ->
      case Repo.get(Request, request_id) do
        nil ->
          Repo.rollback(:not_found)

        %Request{status: "approved"} = req ->
          # Already approved; load the active elevation and return
          # it so the Slack click is harmlessly idempotent.
          case Repo.get_by(Elevation, request_id: req.id) do
            nil -> Repo.rollback(:elevation_missing)
            elev -> {:already_approved, req, elev}
          end

        %Request{status: status} when status != "pending" ->
          Repo.rollback({:invalid_status, status})

        %Request{} = req ->
          cond do
            # The approval window (`@approval_window_seconds`) is the
            # deadline by which a second human must click Approve.
            # The Slack card displays it; until this check existed,
            # the bot wasn't actually enforcing it, so a stale
            # button payload from hours/days ago would still grant
            # access. Transition the request to `expired` (NOT a
            # rollback — we want the status update + Slack card flip
            # to stick) and surface the error up the case below.
            DateTime.before?(req.expires_at, DateTime.utc_now()) ->
              {:ok, expired} =
                req
                |> Request.transition_changeset(%{status: "expired"})
                |> Repo.update()

              notify_closed(expired, "expired")
              {:expired, expired}

            req.requester_slack_id == actor_slack_id and
                not Policy.self_approval_allowed?(actor_email, req.target_group) ->
              Repo.rollback(:cannot_self_approve)

            # Second-human path. Even though the approver is a
            # different person from the requester, we still gate on
            # role: an engineer must not approve another engineer's
            # production write. `approver_allowed?` returns true for
            # Owner/Admin on any env and for Member on staging/
            # canary, matching the self-approve policy's trust tiers.
            req.requester_slack_id != actor_slack_id and
                not Policy.approver_allowed?(actor_email, req.target_group) ->
              Repo.rollback(:approver_not_authorized)

            true ->
              do_approve(req, actor_slack_id, actor_email)
          end
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {:already_approved, req, elev}} ->
        {:ok, req, elev}

      {:ok, {:expired, _req}} ->
        {:error, :approval_expired}

      {:ok, {req, elev}} ->
        {:ok, req, elev}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_approve(req, approver_slack_id, approver_email) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    elev_expires_at = DateTime.add(now, req.ttl_seconds, :second)

    # Elevation is a DB flag, not an ACL mutation. The Pomerium
    # gateway's ext_authz endpoint checks `tailscale_jit_elevations`
    # at request time to decide impersonation; no tailnet policy
    # touch and no propagation delay.
    {:ok, updated_req} =
      req
      |> Request.transition_changeset(%{
        status: "approved",
        approver_slack_id: approver_slack_id,
        approver_email: approver_email,
        approved_at: now
      })
      |> Repo.update()

    {:ok, elev} =
      %{
        request_id: req.id,
        requester_email: req.requester_email,
        target_group: req.target_group,
        expires_at: elev_expires_at
      }
      |> Elevation.create_changeset()
      |> Repo.insert()

    schedule_revert(elev)
    notify_active(updated_req, elev)

    {updated_req, elev}
  end

  @doc """
  Marks the request denied. No ACL touch.
  """
  def deny(request_id, %{slack_id: actor_slack_id, email: actor_email}) do
    Repo.transaction(fn ->
      case Repo.get(Request, request_id) do
        nil ->
          Repo.rollback(:not_found)

        %Request{status: "pending"} = req ->
          {:ok, denied} =
            req
            |> Request.transition_changeset(%{
              status: "denied",
              approver_slack_id: actor_slack_id,
              approver_email: actor_email,
              denied_at: DateTime.truncate(DateTime.utc_now(), :second)
            })
            |> Repo.update()

          notify_closed(denied, "denied")
          denied

        %Request{status: status} ->
          Repo.rollback({:invalid_status, status})
      end
    end)
  end

  @doc """
  Schedules an immediate revert for an elevation. Same code path
  the timed RevertWorker uses; the unique constraint on
  `elevation_id` means a duplicate enqueue is a no-op.
  """
  def revoke(elevation_id, _actor) do
    case Repo.get(Elevation, elevation_id) do
      nil ->
        {:error, :not_found}

      %Elevation{status: "active"} = elev ->
        # The RevertWorker is unique on elevation_id across the
        # available/scheduled/executing/retryable states, so the job
        # we want to fire NOW collides with the TTL-deferred job that
        # `do_approve` enqueued at approval time. Without `replace:`,
        # Oban returns the existing (still-scheduled-for-TTL) job
        # unchanged and the manual revoke silently no-ops. The
        # `replace:` option belongs on `Worker.new/2` (NOT on
        # `Oban.insert/2`), telling Oban: if the conflicting job is
        # in `:scheduled` state, replace its `scheduled_at` with our
        # new value (which `schedule_in: 0` sets to ~now). Same job,
        # uniqueness preserved, runs immediately.
        case %{elevation_id: elev.id}
             |> RevertWorker.new(schedule_in: 0, replace: [scheduled: [:scheduled_at]])
             |> Oban.insert() do
          {:ok, _} -> {:ok, elev}
          {:error, reason} -> {:error, reason}
        end

      %Elevation{status: status} ->
        {:error, {:invalid_status, status}}
    end
  end

  defp schedule_revert(%Elevation{} = elev) do
    schedule_in = max(DateTime.diff(elev.expires_at, DateTime.utc_now()), 0)

    %{elevation_id: elev.id}
    |> RevertWorker.new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  defp notify_active(%Request{} = req, %Elevation{} = elev) do
    SlackClient.update_message(
      req.slack_channel_id,
      req.slack_message_ts,
      SlackBlocks.active(req, elev)
    )
  end

  defp notify_closed(%Request{} = req, label, detail \\ nil) do
    SlackClient.update_message(
      req.slack_channel_id,
      req.slack_message_ts,
      SlackBlocks.closed(req, label, detail)
    )
  end

  defp clamp_ttl(ttl) when is_integer(ttl) and ttl > 0 do
    min(ttl, @max_ttl_seconds)
  end

  defp clamp_ttl(_), do: @default_ttl_seconds

  def default_ttl_seconds, do: @default_ttl_seconds
  def max_ttl_seconds, do: @max_ttl_seconds
  def approval_window_seconds, do: @approval_window_seconds
end
