defmodule Tuist.Automations.Alerts.Alert do
  @moduledoc """
  Represents an alert event in the automation system.

  Alerts are append-only log entries tracking when an alert rule's
  condition was met (status: "triggered") or cleared (status: "recovered")
  for a given entity.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "automation_alerts" do
    field :alert_rule_id, Ecto.UUID
    field :test_case_id, Ecto.UUID
    field :status, Ch, type: "LowCardinality(String)"
    field :triggered_at, Ch, type: "DateTime64(6)"
    field :recovered_at, Ch, type: "Nullable(DateTime64(6))"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:id, :alert_rule_id, :test_case_id, :status, :triggered_at, :recovered_at, :inserted_at])
    |> validate_required([:id, :alert_rule_id, :test_case_id, :status, :triggered_at])
  end
end
