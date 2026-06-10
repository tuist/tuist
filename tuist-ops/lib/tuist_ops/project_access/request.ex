defmodule TuistOps.ProjectAccess.Request do
  @moduledoc """
  An operator's ask to access a customer account through the
  ops.tuist.dev reason form, plus its approval lifecycle.

  Two tiers:

    * `read` — view the customer's dashboard. Auto-approved the
      moment the reason is recorded (the request is created already
      `approved` and immediately spawns a `Grant`).
    * `admin` — act with admin privileges on the customer's org
      ("sign in as admins"). Stays `pending` until a second human
      approves in Slack, exactly like a production kubectl write.

  Goes through: `pending → approved | denied | expired | failed`.
  An approved request spawns a `TuistOps.ProjectAccess.Grant`; the
  grant owns the runtime capability, the request row is the audit of
  who asked, why, and who approved.

  Backed by [priv/repo/migrations/20260610120000_create_project_access_tables.exs](priv/repo/migrations/20260610120000_create_project_access_tables.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending approved denied expired failed)
  @tiers ~w(read admin)

  schema "project_access_requests" do
    field :requester_email, :string
    field :account_handle, :string
    field :tier, :string
    field :reason, :string
    field :return_to, :string
    field :ttl_seconds, :integer
    field :status, :string, default: "pending"
    field :slack_channel_id, :string
    field :slack_message_ts, :string
    field :approver_email, :string
    field :approver_slack_id, :string
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a brand-new request. For the `admin` tier
  `expires_at` is the deadline by which a second human must approve
  in Slack; for the `read` tier it equals the grant's own expiry
  since there is no approval step.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :requester_email,
      :account_handle,
      :tier,
      :reason,
      :return_to,
      :ttl_seconds,
      :status,
      :slack_channel_id,
      :approved_at,
      :expires_at
    ])
    |> validate_required([
      :requester_email,
      :account_handle,
      :tier,
      :reason,
      :return_to,
      :ttl_seconds,
      :expires_at
    ])
    |> validate_inclusion(:tier, @tiers)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> validate_length(:reason, min: 5, max: 500)
  end

  @doc """
  State-transition changeset. The caller picks the new status; the
  inclusion check stays in one place.
  """
  def transition_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :status,
      :slack_message_ts,
      :approver_email,
      :approver_slack_id,
      :approved_at,
      :denied_at,
      :failure_reason
    ])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
  def tiers, do: @tiers
end
