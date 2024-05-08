defmodule TuistCloud.Accounts.Account do
  @moduledoc ~S"""
  A module that represents the accounts table.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias TuistCloud.Billing

  schema "accounts" do
    field :plan, Ecto.Enum, values: [enterprise: 1]
    field :name, :string
    field :owner_type, :string
    field :owner_id, :integer
    field :cache_upload_event_count, :integer
    field :cache_download_event_count, :integer
    field :customer_id, :string

    timestamps(inserted_at: :created_at)
  end

  def create_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :owner_type, :owner_id, :customer_id])
    |> validate_required(
      [:name, :owner_type, :owner_id] ++ if(Billing.enabled?(), do: [:customer_id], else: [])
    )
    |> validate_inclusion(:owner_type, ["User", "Organization"])
    |> unique_constraint(:name, name: "index_accounts_on_owner")
    |> unique_constraint([:owner_id, :owner_type],
      name: "index_accounts_on_owner_id_and_owner_type"
    )
  end
end
