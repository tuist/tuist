defmodule Tuist.Automations.Alerts.PendingTestCaseEvaluation do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "automation_alert_pending_test_case_evaluations" do
    field :alert_id, Ecto.UUID
    field :test_case_id, Ecto.UUID

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
