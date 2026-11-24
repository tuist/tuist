defmodule Symptoms.Store.AuditEvent do
  @moduledoc """
  The audit log: page charges, deploys, version tests, re-anchors, labels and recalibrations.
  """
  use Ecto.Schema

  schema "audit_events" do
    field :kind, :string
    field :entity_id, :integer
    field :symptom_id, Ecto.UUID
    field :data, :map, default: %{}
    field :at, :utc_datetime_usec
  end
end
