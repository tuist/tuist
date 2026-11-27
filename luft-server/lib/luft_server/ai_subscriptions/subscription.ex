defmodule LuftServer.AISubscriptions.Subscription do
  @moduledoc """
  A person's Claude or ChatGPT subscription credentials. Credential fields are
  encrypted and redacted from inspection. Only `LuftServer.AISubscriptions`
  reads these rows.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias LuftServer.AISubscriptions.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "ai_subscriptions" do
    field :user_sub, :string
    field :provider, Ecto.Enum, values: [:claude, :chatgpt]
    field :access_token, EncryptedBinary, redact: true
    field :refresh_token, EncryptedBinary, redact: true
    field :expires_at, :utc_datetime
    # The OAuth client the ChatGPT tokens were issued to; refreshes must use it.
    field :client_id, :string
    # The lease of the refresh in flight, so concurrent readers share it.
    field :refreshing_until, :utc_datetime
    field :pending_login, EncryptedBinary, redact: true
    field :pending_expires_at, :utc_datetime
    field :next_poll_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :access_token,
      :refresh_token,
      :expires_at,
      :client_id,
      :refreshing_until,
      :pending_login,
      :pending_expires_at,
      :next_poll_at
    ])
    |> validate_required([:user_sub, :provider])
    |> unique_constraint([:user_sub, :provider])
  end
end
