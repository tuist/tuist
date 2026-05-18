defmodule Tuist.Automations.Alerts.Event do
  @moduledoc """
  An event emitted when an automation alert fires or recovers.

  Events are append-only log entries tracking when an alert's
  condition was met (status: "triggered") or cleared (status: "recovered")
  for a given entity.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "automation_alert_events" do
    field :alert_id, Ecto.UUID
    field :test_case_id, Ecto.UUID
    field :status, Ch, type: "LowCardinality(String)"
    field :triggered_at, Ch, type: "DateTime64(6)"
    field :recovered_at, Ch, type: "Nullable(DateTime64(6))"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:id, :alert_id, :test_case_id, :status, :triggered_at, :recovered_at, :inserted_at])
    |> validate_required([:id, :alert_id, :test_case_id, :status, :triggered_at])
  end
end
