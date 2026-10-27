defmodule Tuist.Automations.Alerts.BaselineAttempt do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Automations.Alerts.Alert

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "automation_alert_baseline_attempts" do
    field :baseline_generation, :integer
    field :cursor, :utc_datetime
    field :state, :string, default: "evaluating"
    field :evaluation_cursor, :map
    field :last_published_test_case_id, Ecto.UUID

    belongs_to :alert, Alert

    timestamps(type: :utc_datetime)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :alert_id,
      :baseline_generation,
      :cursor,
      :state,
      :evaluation_cursor,
      :last_published_test_case_id
    ])
    |> validate_required([:alert_id, :baseline_generation, :cursor, :state])
    |> validate_inclusion(:state, ["evaluating", "publishing", "committed"])
    |> foreign_key_constraint(:alert_id)
    |> unique_constraint([:alert_id, :baseline_generation])
  end
end
