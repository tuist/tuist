defmodule Tuist.Push.LiveActivity do
  @moduledoc """
  One Luft Live Activity registration: the aggregate activity the app
  started locally for its user's working threads, and the ActivityKit push token
  that updates it. See `Tuist.Push.LiveActivities`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.User
  alias Tuist.Vault.Binary

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "thread_live_activities" do
    belongs_to :user, User
    field :oauth_grant_id, Ecto.UUID
    field :environment, :string
    field :token, Binary, redact: true
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
