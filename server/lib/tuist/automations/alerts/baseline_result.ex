defmodule Tuist.Automations.Alerts.BaselineResult do
  @moduledoc false
  use Ecto.Schema

  alias Tuist.Automations.Alerts.BaselineAttempt

  @primary_key false
  @foreign_key_type UUIDv7

  schema "automation_alert_baseline_results" do
    field :test_case_id, Ecto.UUID, primary_key: true

    belongs_to :attempt, BaselineAttempt, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
