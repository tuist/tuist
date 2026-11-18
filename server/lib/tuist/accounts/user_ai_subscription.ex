defmodule Tuist.Accounts.UserAISubscription do
  @moduledoc """
  A user's personal Claude or ChatGPT subscription credentials. Every
  credential field is encrypted with `Tuist.Vault` and redacted from
  inspection. Only `Tuist.Accounts.AISubscriptions` reads these rows.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User
  alias Tuist.Vault.Binary

  schema "user_ai_subscriptions" do
    belongs_to :user, User
    field :provider, Ecto.Enum, values: [:claude, :chatgpt]
    field :access_token, Binary, redact: true
    field :refresh_token, Binary, redact: true
    field :expires_at, :utc_datetime
    field :pending_login, Binary, redact: true
    field :pending_expires_at, :utc_datetime
    field :next_poll_at, :utc_datetime
    # The lease of the refresh in flight, so concurrent readers share it.
    field :refreshing_until, :utc_datetime
    # The OAuth client the ChatGPT tokens were issued to; refreshes must use it.
    field :client_id, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :provider,
      :access_token,
      :refresh_token,
      :expires_at,
      :pending_login,
      :pending_expires_at,
      :next_poll_at,
      :refreshing_until,
      :client_id
    ])
    |> validate_required([:user_id, :provider])
    |> unique_constraint([:user_id, :provider])
  end
end
