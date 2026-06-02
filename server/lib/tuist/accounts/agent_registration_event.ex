defmodule Tuist.Accounts.AgentRegistrationEvent do
  @moduledoc """
  Append-only audit events for auth.md agent registrations.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.User

  @event_types [:created, :claim_resent, :otp_failed, :claimed, :expired, :revoked]

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "agent_registration_events" do
    field :event_type, Ecto.Enum, values: @event_types
    field :actor_ip, :string
    field :metadata, :map, default: %{}
    field :occurred_at, :utc_datetime

    belongs_to :agent_registration, AgentRegistration, type: UUIDv7
    belongs_to :claimed_by_user, User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :agent_registration_id,
      :event_type,
      :actor_ip,
      :claimed_by_user_id,
      :metadata,
      :occurred_at
    ])
    |> validate_required([:agent_registration_id, :event_type, :occurred_at])
    |> foreign_key_constraint(:agent_registration_id)
    |> foreign_key_constraint(:claimed_by_user_id)
  end
end
