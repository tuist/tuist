defmodule Atlas.LLMs.Connection do
  @moduledoc false
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  schema "user_llm_connections" do
    belongs_to :user, User
    field :provider, :string
    field :access_token, Binary, redact: true
    field :refresh_token, Binary, redact: true
    field :expires_at, :utc_datetime
    field :pending_login, Binary, redact: true
    field :pending_expires_at, :utc_datetime
    field :next_poll_at, :utc_datetime
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
      :next_poll_at
    ])
    |> validate_required([:provider])
    |> validate_inclusion(:provider, ["claude", "chatgpt"])
    |> unique_constraint([:user_id, :provider])
  end
end
