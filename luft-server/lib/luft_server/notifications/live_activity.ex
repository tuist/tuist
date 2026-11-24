defmodule LuftServer.Notifications.LiveActivity do
  @moduledoc "A session-bound ActivityKit registration and monotonic retirement tombstone."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "thread_live_activities" do
    field :user_id, :integer
    # This is the exact Luft session UUID, not a Tuist database/grant reference.
    field :oauth_grant_id, Ecto.UUID
    field :environment, :string
    field :token, LuftServer.Notifications.EncryptedBinary, redact: true
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :last_digest, :binary, redact: true
    field :last_phase_digest, :binary, redact: true
    field :last_sent_at, :utc_datetime
    field :working_thread_ids, {:array, Ecto.UUID}, default: []
    field :retired_at, :utc_datetime
    field :retired_reason, :string
    timestamps(type: :utc_datetime)
  end

  def token_hash(token), do: :crypto.hash(:sha256, ["liveactivity:", token])
end
