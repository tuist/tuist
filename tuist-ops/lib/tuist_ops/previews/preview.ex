defmodule TuistOps.Previews.Request do
  @moduledoc """
  Audit row for a Slack-requested preview action.
  Kubernetes mutation happens in GitHub Actions; this row records who asked,
  why, which workflow was dispatched, and the TTL metadata the sweeper uses.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @actions ~w(create delete)
  @statuses ~w(requested provisioning deleting failed)

  schema "preview_requests" do
    field :slug, :string
    field :action, :string
    field :status, :string, default: "requested"
    field :requester_email, :string
    field :requester_slack_id, :string
    field :ref_kind, :string
    field :ref_value, :string
    field :reason, :string
    field :ttl_seconds, :integer
    field :host, :string
    field :namespace, :string
    field :release, :string
    field :slack_channel_id, :string
    field :slack_message_ts, :string
    field :workflow_id, :string
    field :workflow_ref, :string
    field :expires_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :slug,
      :action,
      :status,
      :requester_email,
      :requester_slack_id,
      :ref_kind,
      :ref_value,
      :reason,
      :ttl_seconds,
      :host,
      :namespace,
      :release,
      :slack_channel_id,
      :slack_message_ts,
      :workflow_id,
      :workflow_ref,
      :expires_at,
      :failed_at,
      :failure_reason
    ])
    |> validate_required([
      :slug,
      :action,
      :status,
      :requester_email,
      :requester_slack_id,
      :reason,
      :slack_channel_id
    ])
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$/)
    |> validate_length(:reason, min: 5)
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> unique_constraint(:slug, name: :preview_requests_active_create_slug_index)
  end

  def transition_changeset(%__MODULE__{} = request, attrs) do
    request
    |> cast(attrs, [
      :status,
      :slack_message_ts,
      :workflow_id,
      :workflow_ref,
      :failed_at,
      :failure_reason
    ])
    |> validate_inclusion(:status, @statuses)
  end
end
