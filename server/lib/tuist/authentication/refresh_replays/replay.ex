defmodule Tuist.Authentication.RefreshReplays.Replay do
  @moduledoc false

  use Ecto.Schema

  alias Tuist.Vault.Binary

  @primary_key false
  schema "refresh_token_replays" do
    field :kind, :string, primary_key: true
    field :token_hash, :binary, primary_key: true
    field :credential_hash, :binary
    field :response, Binary, redact: true
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
