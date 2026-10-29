defmodule Atlas.Accounts.AccountHandle do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  schema "account_handles" do
    field :handle, :string
    field :source, :string

    belongs_to :account, Account

    timestamps()
  end

  def changeset(account_handle, attrs) do
    account_handle
    |> cast(attrs, [:handle, :source, :account_id])
    |> update_change(:handle, &String.trim/1)
    |> validate_required([:handle, :source, :account_id])
    |> unique_constraint(:handle, name: :account_handles_handle_index)
  end
end
