defmodule Atlas.Presence.Connection do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "presence_connections" do
    field :user_id, Ecto.UUID, primary_key: true
    field :connection_id, Ecto.UUID, primary_key: true
    field :location, :string
    field :expires_at, :utc_datetime_usec
  end
end
