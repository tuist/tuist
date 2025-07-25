defmodule Tuist.Accounts.AccountToken do
  @moduledoc ~S"""
  A module that represents the account_tokens table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "account_tokens" do
    field :encrypted_token_hash, :string

    field :scopes, {:array, Ecto.Enum},
      values: [account_registry_read: 0, project_qa_run_update: 1, project_qa_run_step_create: 2]

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(account, attrs) do
    account
    |> cast(attrs, [:account_id, :encrypted_token_hash, :scopes])
    |> validate_required([:account_id, :encrypted_token_hash, :scopes])
    |> validate_subset(:scopes, Ecto.Enum.values(__MODULE__, :scopes))
    |> unique_constraint([:account_id, :encrypted_token_hash])
  end
end
