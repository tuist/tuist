defmodule TuistOps.Previews.Preview do
  @moduledoc """
  One row per Slack-requested preview. Slug is the natural key; status
  tracks lifecycle.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(creating active deleting deleted failed)

  schema "previews" do
    field :slug, :string
    field :status, :string, default: "creating"
    field :requester_email, :string
    field :requester_slack_id, :string
    field :ref_kind, :string
    field :ref_value, :string
    field :reason, :string
    field :ttl_seconds, :integer
    field :host, :string
    field :slack_channel_id, :string
    field :slack_message_ts, :string
    field :deleted_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Whether the preview is still in flight (a fresh `/preview create` for the
  same slug should be rejected).
  """
  def active_status?(status) when is_binary(status), do: status in ~w(creating active)
  def active_status?(_), do: false

  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs, [
      :slug,
      :status,
      :requester_email,
      :requester_slack_id,
      :ref_kind,
      :ref_value,
      :reason,
      :ttl_seconds,
      :host,
      :slack_channel_id,
      :slack_message_ts,
      :deleted_at,
      :failed_at,
      :failure_reason
    ])
    |> validate_required([
      :slug,
      :status,
      :requester_email,
      :requester_slack_id,
      :reason,
      :slack_channel_id
    ])
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$/)
    |> validate_length(:reason, min: 5)
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> unique_constraint(:slug)
  end

  def transition_changeset(%__MODULE__{} = preview, attrs) do
    changeset(preview, attrs, [
      :status,
      :ref_kind,
      :ref_value,
      :reason,
      :ttl_seconds,
      :slack_channel_id,
      :slack_message_ts,
      :deleted_at,
      :failed_at,
      :failure_reason
    ])
  end

  defp changeset(struct, attrs, fields) do
    struct
    |> cast(attrs, fields)
    |> validate_inclusion(:status, @statuses)
  end
end
