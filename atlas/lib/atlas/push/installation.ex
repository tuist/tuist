defmodule Atlas.Push.Installation do
  @moduledoc """
  One native app installation's push registration on this Atlas server.

  `id` is the server-owned registration ID returned to clients and carried in
  delivery payloads. `installation_id` is the client-generated UUID from the
  route. A retired row is a tombstone: its token and owner are cleared, and the
  installation ID can never be registered again, so stale requests cannot
  resurrect it. Clients rotate to a new installation ID instead.
  """
  use Atlas.Schema

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  @retired_reasons ~w(unregistered owner_changed superseded provider_invalidated session_ended stale evicted)

  schema "push_installations" do
    field :installation_id, Ecto.UUID
    belongs_to :user, User
    field :oauth_client_id, :string
    field :platform, :string
    field :environment, :string
    field :token, Binary, redact: true
    field :token_hash, :binary, redact: true
    field :token_updated_at, :utc_datetime_usec
    field :last_registered_at, :utc_datetime_usec
    field :retired_at, :utc_datetime_usec
    field :retired_reason, :string
    timestamps(type: :utc_datetime_usec)
  end

  def retired_reasons, do: @retired_reasons

  def live?(%__MODULE__{retired_at: nil}), do: true
  def live?(%__MODULE__{}), do: false

  @doc "SHA-256 of the platform and token. Device tokens are high-entropy, so no key is needed."
  def token_hash(platform, token), do: :crypto.hash(:sha256, [platform, ":", token])
end
