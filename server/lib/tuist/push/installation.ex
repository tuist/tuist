defmodule Tuist.Push.Installation do
  @moduledoc """
  One native app installation's push registration.

  `id` is the server-owned registration ID returned to clients. `installation_id`
  is the client-generated UUID from the route. A retired row is a tombstone: its
  owner, grant and token are cleared, and its installation ID can never be
  registered again, so stale requests cannot resurrect it. Clients rotate to a
  new installation ID instead.
  """
  use Ecto.Schema

  alias Tuist.Accounts.User
  alias Tuist.Vault.Binary

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "push_installations" do
    field :installation_id, Ecto.UUID
    belongs_to :user, User
    field :oauth_grant_id, Ecto.UUID
    field :platform, :string
    field :device_name, :string
    field :environment, :string
    field :token, Binary, redact: true
    field :token_hash, :binary, redact: true
    field :last_registered_at, :utc_datetime
    field :retired_at, :utc_datetime
    field :retired_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc "SHA-256 of the platform and token. Device tokens are high-entropy, so no key is needed."
  def token_hash(platform, token), do: :crypto.hash(:sha256, [platform, ":", token])
end
