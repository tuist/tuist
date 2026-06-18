defmodule TuistOps.Previews.Preview do
  @moduledoc """
  Single row representing a Slack-requested preview's current state.

  Slug is the natural key: `/preview create demo` and a later
  `/preview delete demo` always converge to the same row. Status describes
  what we last asked the workflow to do with the preview — there's no
  GH Actions completion callback yet, so a successful create leaves the
  row at `creating` indefinitely. That's fine for the state model: the row
  still represents the preview, and the next slug-targeted command mutates
  it in place.
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
    field :namespace, :string
    field :release, :string
    field :slack_channel_id, :string
    field :slack_message_ts, :string
    field :workflow_id, :string
    field :workflow_ref, :string
    field :expires_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns whether the preview is in a state where a fresh `/preview create`
  for the same slug should be rejected. `creating` / `active` / `deleting`
  are still in flight; `deleted` / `failed` are terminal and free for reuse.
  """
  def active_status?(status) when is_binary(status) do
    status in ~w(creating active deleting)
  end

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
      :namespace,
      :release,
      :slack_channel_id,
      :slack_message_ts,
      :workflow_id,
      :workflow_ref,
      :expires_at,
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
      :workflow_id,
      :workflow_ref,
      :expires_at,
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
