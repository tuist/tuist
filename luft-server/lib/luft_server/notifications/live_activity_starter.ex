defmodule LuftServer.Notifications.LiveActivityStarter do
  @moduledoc "A push-to-start token belonging to one exact Luft sign-in."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_live_activity_starters" do
    field :user_id, :integer
    field :oauth_grant_id, Ecto.UUID
    field :profile_id, :string
    field :environment, :string
    field :token, LuftServer.Notifications.EncryptedBinary, redact: true
    field :token_hash, :binary, redact: true
    field :last_start_id, Ecto.UUID
    field :last_started_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def token_hash(token), do: :crypto.hash(:sha256, ["liveactivity-start:", token])
end
