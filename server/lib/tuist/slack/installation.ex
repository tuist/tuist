defmodule Tuist.Slack.Installation do
  @moduledoc """
  A module that represents Slack app installations for accounts.

  Installations created before Slack token rotation hold a long-lived bot
  token and no `refresh_token`. Once exchanged (see
  `Tuist.Slack.installation_access_token/1`), `access_token` expires at
  `access_token_expires_at` and is replaced with `refresh_token`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "slack_installations" do
    field :team_id, :string
    field :team_name, :string
    field :access_token, Binary, redact: true
    field :bot_user_id, :string
    field :refresh_token, Binary, redact: true
    field :access_token_expires_at, :utc_datetime

    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(installation \\ %__MODULE__{}, attrs) do
    installation
    |> cast(attrs, [
      :account_id,
      :team_id,
      :team_name,
      :access_token,
      :bot_user_id,
      :refresh_token,
      :access_token_expires_at
    ])
    |> validate_required([:account_id, :team_id, :access_token])
    |> unique_constraint([:account_id])
    |> unique_constraint([:team_id])
    |> foreign_key_constraint(:account_id)
  end
end
