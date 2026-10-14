defmodule Tuist.Origin.Installation do
  @moduledoc """
  Links an Origin namespace's app installation to one Tuist account.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "origin_app_installations" do
    field :installation_id, :string
    field :namespace_id, :string
    field :namespace_slug, :string
    field :scopes, {:array, :string}, default: []
    field :suspended, :boolean, default: false
    belongs_to :account, Account
    timestamps(type: :utc_datetime)
  end

  def changeset(installation \\ %__MODULE__{}, attrs) do
    installation
    |> cast(attrs, [:account_id, :installation_id, :namespace_id, :namespace_slug, :scopes, :suspended])
    |> validate_required([:account_id, :installation_id, :namespace_id, :namespace_slug])
    |> unique_constraint(:account_id)
    |> unique_constraint(:installation_id)
    |> unique_constraint(:namespace_id)
    |> foreign_key_constraint(:account_id)
  end
end
