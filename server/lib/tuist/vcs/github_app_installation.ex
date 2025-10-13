defmodule Tuist.VCS.GitHubAppInstallation do
  @moduledoc """
  A module that represents GitHub app installations for accounts.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "github_app_installations" do
    field :installation_id, :string
    field :html_url, :string

    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(github_app_installation \\ %__MODULE__{}, attrs) do
    github_app_installation
    |> cast(attrs, [:account_id, :installation_id, :html_url])
    |> validate_required([:account_id, :installation_id])
    |> unique_constraint([:account_id])
    |> unique_constraint([:installation_id])
    |> foreign_key_constraint(:account_id)
  end

  def update_changeset(github_app_installation, attrs) do
    github_app_installation
    |> cast(attrs, [:html_url])
    |> validate_required([])
  end
end
