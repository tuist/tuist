defmodule Atlas.Connections.Authorization do
  @moduledoc false
  use Ecto.Schema

  alias Atlas.Users.User

  @primary_key {:nonce_hash, :binary, autogenerate: false}
  @foreign_key_type :binary_id
  schema "user_connection_authorizations" do
    belongs_to :user, User
    field :provider, :string
    field :expires_at, :utc_datetime
  end
end
