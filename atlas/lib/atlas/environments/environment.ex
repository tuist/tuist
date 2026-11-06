defmodule Atlas.Environments.Environment do
  @moduledoc false
  use Atlas.Schema

  schema "personal_environments" do
    field :owner_id, Ecto.UUID
    field :oauth_client_id, Ecto.UUID
    field :provider, :string, default: "native"
    field :provider_state, :string
    field :managed_thread_id, Ecto.UUID
    field :name, :string
    field :enabled, :boolean, default: false
    field :terminal, :boolean, default: false
    field :display, :boolean, default: false
    field :projects, {:array, :map}, default: []
    field :version, :integer, default: 1
    field :online_until, :utc_datetime_usec
    field :connection_id, Ecto.UUID
    timestamps(type: :utc_datetime_usec)
  end
end
