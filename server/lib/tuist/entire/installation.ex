defmodule Tuist.Entire.Installation do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "ci_installations" do
    belongs_to :account, Tuist.Accounts.Account
    field :remote_id, :string
    field :active, :boolean, default: true
    field :revision, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [:account_id, :remote_id, :active])
    |> validate_required([:account_id, :remote_id])
    |> unique_constraint(:remote_id)
    |> foreign_key_constraint(:account_id)
  end
end
