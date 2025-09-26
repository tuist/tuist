defmodule Tuist.Accounts.GitHubAppInstallation do
  @moduledoc """
  A module that represents GitHub app installations for accounts.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "github_app_installations" do
    field :installation_id, :string

    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(github_app_installation \\ %__MODULE__{}, attrs) do
    github_app_installation
    |> cast(attrs, [:account_id, :installation_id])
    |> validate_required([:account_id, :installation_id])
    |> unique_constraint([:account_id])
    |> unique_constraint([:installation_id])
    |> foreign_key_constraint(:account_id)
  end
end
