defmodule Tuist.Automations.Builds.Finding do
  @moduledoc "A persistent, notification-deduplicated cache-key inconsistency."
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "build_automation_findings" do
    field :alert_id, UUIDv7
    field :source, :string
    field :unit_id, :string
    field :evidence, :map
    field :notification_batch, Ecto.UUID
    field :notified_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
