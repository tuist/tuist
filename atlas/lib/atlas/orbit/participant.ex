defmodule Atlas.Orbit.Participant do
  @moduledoc false
  use Ecto.Schema

  alias Atlas.Orbit.Thread
  alias Atlas.Users.User

  @primary_key false
  @foreign_key_type Atlas.UUIDv7

  schema "orbit_participants" do
    belongs_to :thread, Thread, primary_key: true
    belongs_to :user, User, primary_key: true
    field :role, :string, default: "member"

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
