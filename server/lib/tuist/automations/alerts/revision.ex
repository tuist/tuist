defmodule Tuist.Automations.Alerts.Revision do
  @moduledoc """
  An append-only record of a change to an automation alert's configuration.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User
  alias Tuist.Automations.Alerts.Alert

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "automation_alert_revisions" do
    field :event, :string
    field :source, :string
    field :changes, :map, default: %{}
    field :snapshot, :map, default: %{}

    belongs_to :automation_alert, Alert
    belongs_to :actor, User, type: :integer

    timestamps(updated_at: false, type: :utc_datetime)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:automation_alert_id, :actor_id, :event, :source, :changes, :snapshot, :inserted_at])
    |> validate_required([:automation_alert_id, :event, :source, :snapshot])
    |> validate_inclusion(:event, ~w(created updated))
    |> foreign_key_constraint(:automation_alert_id)
    |> foreign_key_constraint(:actor_id)
  end
end
