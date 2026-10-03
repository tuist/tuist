defmodule Atlas.Engineering.Alerts.Notification do
  @moduledoc """
  Records that a rule fired for a given subject at a given time.

  Rows here back the per-rule cooldown check (was this rule's subject
  notified in the last N minutes?) and give operators an audit trail of
  what actually went out, including delivery status on failure.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Alerts.Rule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:sent, :failed, :skipped]
  @subject_types [:error_issue]

  schema "alert_notifications" do
    field :subject_type, Ecto.Enum, values: @subject_types
    field :subject_id, :binary_id
    field :status, Ecto.Enum, values: @statuses
    field :fired_at, :utc_datetime_usec
    field :metadata, :map, default: %{}
    field :last_error, :string

    belongs_to :rule, Rule

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :rule_id,
      :subject_type,
      :subject_id,
      :status,
      :fired_at,
      :metadata,
      :last_error
    ])
    |> validate_required([:rule_id, :subject_type, :subject_id, :status, :fired_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:subject_type, @subject_types)
  end
end
