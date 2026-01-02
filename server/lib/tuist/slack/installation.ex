defmodule Tuist.Slack.Installation do
  @moduledoc """
  A module that represents Slack app installations for accounts.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "slack_installations" do
    field :team_id, :string
    field :team_name, :string
    field :access_token, Tuist.Vault.Binary
    field :bot_user_id, :string

    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(installation \\ %__MODULE__{}, attrs) do
    installation
    |> cast(attrs, [:account_id, :team_id, :team_name, :access_token, :bot_user_id])
    |> validate_required([:account_id, :team_id, :access_token])
    |> unique_constraint([:account_id])
    |> unique_constraint([:team_id])
    |> foreign_key_constraint(:account_id)
  end
end
