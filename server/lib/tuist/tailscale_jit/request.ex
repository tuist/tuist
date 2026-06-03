defmodule Tuist.TailscaleJIT.Request do
  @moduledoc """
  A Slack-side elevation request: someone asked to be added to a
  break-glass Tailscale group for a bounded session, and the
  approval lifecycle for that ask. Goes through:
  `pending → approved | denied | expired | failed | cancelled`.

  An approved request spawns a `Tuist.TailscaleJIT.Elevation`; the
  request row is not touched after approval, the elevation owns the
  runtime state.

  Backed by [priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs](priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending approved denied expired failed cancelled)

  schema "tailscale_jit_requests" do
    field :requester_email, :string
    field :requester_slack_id, :string
    field :target_group, :string
    field :intent, :string
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
  Changeset for a brand-new request, before any approval activity.
  `expires_at` here is the deadline by which a second human must
  approve in Slack (default 10 minutes); the runtime elevation TTL
  lives on the Elevation row instead.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :requester_email,
      :requester_slack_id,
      :target_group,
      :intent,
      :ttl_seconds,
      :slack_channel_id,
      :expires_at
    ])
    |> validate_required([
      :requester_email,
      :requester_slack_id,
      :target_group,
      :intent,
      :ttl_seconds,
      :slack_channel_id,
      :expires_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:ttl_seconds, greater_than: 0, less_than_or_equal_to: 3600)
    |> validate_length(:intent, min: 5, max: 500)
  end

  @doc """
  State-transition changeset. Caller picks the new status; this
  exists so transitions are explicit and the inclusion check stays
  in one place.
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
end
