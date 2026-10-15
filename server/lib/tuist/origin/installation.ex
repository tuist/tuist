defmodule Tuist.Origin.Installation do
  @moduledoc "Durable, account-owned Origin app installation. App keys remain deployment secrets."
  use Ecto.Schema
  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "origin_app_installations" do
    field :installation_id, :string
    field :app_id, :string
    field :namespace_id, :string
    belongs_to :account, Account, type: :integer
    timestamps(type: :utc_datetime)
  end

  def changeset(installation \\ %__MODULE__{}, attrs) do
    installation
    |> cast(attrs, [:installation_id, :app_id, :namespace_id, :account_id])
    |> validate_required([:installation_id, :app_id, :namespace_id, :account_id])
    |> unique_constraint([:app_id, :installation_id])
    |> foreign_key_constraint(:account_id)
  end
end
