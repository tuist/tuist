defmodule Tuist.TailscaleJIT.Approvals do
  @moduledoc """
  Public API for the JIT elevation bot. Four operations:

    * `request_elevation/1` — create a Request, post the Slack card,
      return the persisted Request.
    * `approve/2` — second human says yes. Double-checks
      approver_slack_id != requester_slack_id, mutates the
      Tailscale ACL to add the requester to the break-glass group,
      creates an Elevation, schedules a revert, updates Slack.
    * `deny/2` — second human says no. Updates Slack, no ACL touch.
    * `revoke/2` — early revert. Enqueues the revert worker now.

  All state transitions write the row before any side effect; ACL
  mutation uses set semantics so retries are safe.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.TailscaleJIT.ACLMutation
  alias Tuist.TailscaleJIT.Elevation
  alias Tuist.TailscaleJIT.Request
  alias Tuist.TailscaleJIT.SlackBlocks
  alias Tuist.TailscaleJIT.SlackClient
  alias Tuist.TailscaleJIT.TailscaleClient
  alias Tuist.TailscaleJIT.Workers.RevertWorker

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
    expires_at = DateTime.utc_now() |> DateTime.add(@approval_window_seconds, :second)

    changeset =
      attrs
      |> Map.put(:ttl_seconds, ttl)
      |> Map.put(:expires_at, expires_at)
      |> Request.create_changeset()

    with {:ok, request} <- Repo.insert(changeset),
         {:ok, ts} <- SlackClient.post_message(request.slack_channel_id, SlackBlocks.pending(request)) do
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
    Repo.transaction(fn ->
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

        %Request{requester_slack_id: ^actor_slack_id} ->
          # Defence-in-depth: the controller already checks this
          # from the button value, but enforce again inside the
          # transaction so a buggy or skipped pre-check still fails
          # closed.
          Repo.rollback(:cannot_self_approve)

        %Request{} = req ->
          do_approve(req, actor_slack_id, actor_email)
      end
    end)
    |> case do
      {:ok, {:already_approved, req, elev}} ->
        {:ok, req, elev}

      {:ok, {req, elev}} ->
        {:ok, req, elev}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_approve(req, approver_slack_id, approver_email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    elev_expires_at = DateTime.add(now, req.ttl_seconds, :second)

    case mutate_acl_add(req.requester_email, req.target_group) do
      {:ok, _} ->
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

      {:error, reason} ->
        # Mark the request as failed so the Slack thread reflects
        # reality and the operator sees something went wrong.
        {:ok, _} =
          req
          |> Request.transition_changeset(%{status: "failed", failure_reason: inspect(reason)})
          |> Repo.update()

        Repo.rollback({:acl_mutation_failed, reason})
    end
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
              denied_at: DateTime.utc_now() |> DateTime.truncate(:second)
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
        case %{elevation_id: elev.id} |> RevertWorker.new(schedule_in: 0) |> Oban.insert() do
          {:ok, _} -> {:ok, elev}
          {:error, reason} -> {:error, reason}
        end

      %Elevation{status: status} ->
        {:error, {:invalid_status, status}}
    end
  end

  @doc """
  Re-queues reverts for all `:active` elevations whose expiry has
  already passed. Called from `Tuist.TailscaleJIT.Reconciler` on
  boot to catch the gap between a missed Oban job and the next
  cron tick.
  """
  def re_enqueue_expired_active_elevations do
    now = DateTime.utc_now()

    from(e in Elevation, where: e.status == "active" and e.expires_at <= ^now)
    |> Repo.all()
    |> Enum.each(fn elev ->
      _ = %{elevation_id: elev.id} |> RevertWorker.new() |> Oban.insert()
    end)
  end

  # Wraps the ACL mutation behind a single function so the worker
  # and the approval flow share a single set-semantics path.
  defp mutate_acl_add(member_email, target_group) do
    TailscaleClient.update_acl(fn doc ->
      ACLMutation.add_member(doc, target_group, member_email)
    end)
  end

  defp schedule_revert(%Elevation{} = elev) do
    schedule_in = max(DateTime.diff(elev.expires_at, DateTime.utc_now()), 0)

    %{elevation_id: elev.id}
    |> RevertWorker.new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  defp notify_active(%Request{} = req, %Elevation{} = elev) do
    SlackClient.update_message(req.slack_channel_id, req.slack_message_ts, SlackBlocks.active(req, elev))
  end

  defp notify_closed(%Request{} = req, label, detail \\ nil) do
    SlackClient.update_message(req.slack_channel_id, req.slack_message_ts, SlackBlocks.closed(req, label, detail))
  end

  defp clamp_ttl(ttl) when is_integer(ttl) and ttl > 0 do
    min(ttl, @max_ttl_seconds)
  end

  defp clamp_ttl(_), do: @default_ttl_seconds

  def default_ttl_seconds, do: @default_ttl_seconds
  def max_ttl_seconds, do: @max_ttl_seconds
  def approval_window_seconds, do: @approval_window_seconds
end
