defmodule Atlas.Push.LiveActivity do
  @moduledoc "Encrypted, short-lived ActivityKit registration; retired IDs are tombstones."
  use Atlas.Schema

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  schema "orbit_live_activities" do
    belongs_to :user, User
    field :oauth_client_id, :string
    field :token, Binary, redact: true
    field :token_hash, :binary, redact: true
    field :environment, :string
    field :expires_at, :utc_datetime_usec
    field :retired_at, :utc_datetime_usec
    field :last_fingerprint, :binary, redact: true
    field :last_timestamp, :integer
    field :last_sent_at, :utc_datetime_usec
    field :reconciled_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
