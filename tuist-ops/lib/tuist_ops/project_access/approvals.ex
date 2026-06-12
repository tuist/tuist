defmodule TuistOps.ProjectAccess.Approvals do
  @moduledoc """
  Public API for operator access to customer projects. The state
  machine behind the ops.tuist.dev reason form.

    * `request_access/1` — an operator submitted the reason form.
      For `read` it creates an already-approved Request and spawns a
      Grant inline (returns `{:ok, :granted, grant}`). For `admin` it
      creates a `pending` Request and posts a Slack approval card
      (returns `{:ok, :pending, request}`).
    * `approve/2` — a second human clicked Approve on an admin
      request in Slack. Gates self-approval out entirely (admin
      access always needs a second human) and requires the approver
      to be an Owner/Admin on the tailnet, then spawns the Grant.
    * `deny/2` — a second human clicked Deny.

  The Grant row is the audit record; the signed token the customer
  server verifies is minted from it by `TuistOps.ProjectAccess.Token`
  (read tier: by the controller right after this returns; admin tier:
  by the pending-page status endpoint once the Grant exists).
  """

  import Ecto.Query, only: [from: 2]

  alias TuistOps.JIT.SlackClient
  alias TuistOps.ProjectAccess.Grant
  alias TuistOps.ProjectAccess.Policy
  alias TuistOps.ProjectAccess.Request
  alias TuistOps.ProjectAccess.SlackBlocks
  alias TuistOps.Repo

  require Logger

  # A second human has this long to click Approve on an admin
  # request. Independent of the grant TTL (the runtime access length).
  @approval_window_seconds 600
  # Read is low blast radius — viewing a dashboard — so a slightly
  # longer default. Admin mirrors the tight kubectl-write bounds:
  # short sessions mean fresh attestation of intent.
  @read_default_ttl_seconds 30 * 60
  @read_max_ttl_seconds 60 * 60
  @admin_default_ttl_seconds 30 * 60
  @admin_max_ttl_seconds 30 * 60

  @fallback_text "Operator admin access request"

  @doc """
  Handles a submitted reason form. `attrs` must include
  `:requester_email`, `:account_handle`, `:tier` (`"read"`/`"admin"`),
  `:reason`, `:return_to`, and may include `:ttl_seconds`. Admin
  requests also need `:slack_channel_id`.
  """
  def request_access(%{tier: "read"} = attrs) do
    ttl =
      clamp_ttl(Map.get(attrs, :ttl_seconds), @read_default_ttl_seconds, @read_max_ttl_seconds)

    now = now()
    expires_at = DateTime.add(now, ttl, :second)

    Repo.transaction(fn ->
      request =
        attrs
        |> request_attrs(ttl, expires_at)
        |> Map.merge(%{status: "approved", approved_at: now})
        |> Request.create_changeset()
        |> Repo.insert!()

      grant =
        request
        |> grant_attrs(expires_at)
        |> Grant.create_changeset()
        |> Repo.insert!()

      {request, grant}
    end)
    |> case do
      {:ok, {_request, grant}} -> {:ok, :granted, grant}
      {:error, reason} -> {:error, reason}
    end
  end

  def request_access(%{tier: "admin"} = attrs) do
    ttl =
      clamp_ttl(Map.get(attrs, :ttl_seconds), @admin_default_ttl_seconds, @admin_max_ttl_seconds)

    approval_expires_at = DateTime.add(now(), @approval_window_seconds, :second)
    channel_id = Map.get(attrs, :slack_channel_id)

    with {:ok, request} <-
           attrs
           |> request_attrs(ttl, approval_expires_at)
           |> Map.put(:slack_channel_id, channel_id)
           |> Request.create_changeset()
           |> Repo.insert(),
         {:ok, ts} <-
           SlackClient.post_message(channel_id, SlackBlocks.pending(request),
             fallback_text: @fallback_text
           ),
         {:ok, updated} <-
           request |> Request.transition_changeset(%{slack_message_ts: ts}) |> Repo.update() do
      {:ok, :pending, updated}
    else
      {:error, reason} ->
        Logger.warning("project_access: request_access(admin) failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Approves an admin request. `actor` is the Slack user who clicked
  Approve. Admin access to a customer org always needs a second
  human, so the requester can never self-approve, and the approver
  must be an Owner/Admin on the tailnet. Idempotent on replay.
  """
  def approve(request_id, %{slack_id: actor_slack_id, email: actor_email}) do
    fn ->
      case Repo.one(from r in Request, where: r.id == ^request_id, lock: "FOR UPDATE") do
        nil ->
          Repo.rollback(:not_found)

        %Request{status: "approved"} = req ->
          case Repo.get_by(Grant, request_id: req.id) do
            nil -> Repo.rollback(:grant_missing)
            grant -> {:already_approved, req, grant}
          end

        %Request{status: status} when status != "pending" ->
          Repo.rollback({:invalid_status, status})

        %Request{} = req ->
          cond do
            DateTime.before?(req.expires_at, DateTime.utc_now()) ->
              {:ok, expired} =
                req |> Request.transition_changeset(%{status: "expired"}) |> Repo.update()

              notify_closed(expired, "expired")
              {:expired, expired}

            String.downcase(req.requester_email) == String.downcase(actor_email) ->
              Repo.rollback(:cannot_self_approve)

            not Policy.admin_approver_allowed?(actor_email) ->
              Repo.rollback(:approver_not_authorized)

            true ->
              do_approve(req, actor_slack_id, actor_email)
          end
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {:already_approved, req, grant}} -> {:ok, req, grant}
      {:ok, {:expired, _req}} -> {:error, :approval_expired}
      {:ok, {req, grant}} -> {:ok, req, grant}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Marks an admin request denied. No grant created.
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
  Fetches a request by id (used by the pending-page status endpoint).
  Tolerates a non-numeric path param by returning nil.
  """
  def get_request(id) when is_integer(id), do: Repo.get(Request, id)

  def get_request(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> Repo.get(Request, int)
      _ -> nil
    end
  end

  @doc """
  Returns the active grant for a request, or nil.
  """
  def active_grant_for_request(request_id) do
    Repo.get_by(Grant, request_id: request_id, status: "active")
  end

  def read_default_ttl_seconds, do: @read_default_ttl_seconds
  def read_max_ttl_seconds, do: @read_max_ttl_seconds
  def admin_default_ttl_seconds, do: @admin_default_ttl_seconds
  def admin_max_ttl_seconds, do: @admin_max_ttl_seconds
  def approval_window_seconds, do: @approval_window_seconds

  defp do_approve(req, approver_slack_id, approver_email) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    grant_expires_at = DateTime.add(now, req.ttl_seconds, :second)

    {:ok, updated_req} =
      req
      |> Request.transition_changeset(%{
        status: "approved",
        approver_slack_id: approver_slack_id,
        approver_email: approver_email,
        approved_at: now
      })
      |> Repo.update()

    {:ok, grant} =
      updated_req
      |> grant_attrs(grant_expires_at)
      |> Grant.create_changeset()
      |> Repo.insert()

    notify_active(updated_req, grant)
    {updated_req, grant}
  end

  defp request_attrs(attrs, ttl, expires_at) do
    %{
      requester_email: Map.fetch!(attrs, :requester_email),
      account_handle: Map.fetch!(attrs, :account_handle),
      tier: Map.fetch!(attrs, :tier),
      reason: Map.fetch!(attrs, :reason),
      return_to: Map.fetch!(attrs, :return_to),
      ttl_seconds: ttl,
      expires_at: expires_at
    }
  end

  defp grant_attrs(%Request{} = request, expires_at) do
    %{
      request_id: request.id,
      requester_email: request.requester_email,
      account_handle: request.account_handle,
      tier: request.tier,
      reason: request.reason,
      expires_at: expires_at
    }
  end

  defp notify_active(%Request{slack_channel_id: nil}, _grant), do: :ok

  defp notify_active(%Request{} = req, %Grant{} = grant) do
    SlackClient.update_message(
      req.slack_channel_id,
      req.slack_message_ts,
      SlackBlocks.active(req, grant),
      fallback_text: @fallback_text
    )
  end

  defp notify_closed(%Request{slack_channel_id: nil}, _label), do: :ok

  defp notify_closed(%Request{} = req, label) do
    SlackClient.update_message(
      req.slack_channel_id,
      req.slack_message_ts,
      SlackBlocks.closed(req, label),
      fallback_text: @fallback_text
    )
  end

  defp clamp_ttl(nil, default, _max), do: default
  defp clamp_ttl(ttl, _default, max) when is_integer(ttl) and ttl > 0, do: min(ttl, max)
  defp clamp_ttl(_, default, _max), do: default

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
