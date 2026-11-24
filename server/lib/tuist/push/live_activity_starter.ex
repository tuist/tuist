defmodule Tuist.Push.LiveActivityStarter do
  @moduledoc """
  The ActivityKit push-to-start token of one Luft sign-in, which lets the server
  start the threads Live Activity while the app isn't open. One row per sign-in
  and per token. See `Tuist.Push.LiveActivities`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.User
  alias Tuist.Vault.Binary

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_live_activity_starters" do
    belongs_to :user, User
    field :oauth_grant_id, Ecto.UUID
    # The app's local ID for the Luft profile of the sign-in, echoed in the
    # activity's attributes so the app can tell which profile it belongs to.
    field :profile_id, :string
    field :environment, :string
    field :token, Binary, redact: true
    field :token_hash, :binary, redact: true
    # The registration of the last activity the server started here and when,
    # which hold off the next start while the device never registered it.
    field :last_start_id, Ecto.UUID
    field :last_started_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def token_hash(token), do: :crypto.hash(:sha256, ["liveactivity-start:", token])
end
