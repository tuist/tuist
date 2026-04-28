defmodule Tuist.VCS.GitHubAppInstallation do
  @moduledoc """
  A module that represents GitHub app installations for accounts.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.VCS

  @default_client_url "https://github.com"

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "github_app_installations" do
    field :installation_id, :string
    field :html_url, :string
    field :client_url, :string, default: @default_client_url

    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(github_app_installation \\ %__MODULE__{}, attrs) do
    github_app_installation
    |> cast(attrs, [:account_id, :installation_id, :html_url, :client_url])
    |> normalize_client_url()
    |> validate_required([:account_id, :installation_id, :client_url])
    |> validate_change(:client_url, fn :client_url, value ->
      case VCS.validate_client_url(value) do
        {:ok, _} -> []
        {:error, _} -> [client_url: "must be a valid URL like https://github.example.com"]
      end
    end)
    |> unique_constraint([:account_id])
    |> unique_constraint([:installation_id])
    |> foreign_key_constraint(:account_id)
  end

  def update_changeset(github_app_installation, attrs) do
    github_app_installation
    |> cast(attrs, [:html_url])
    |> validate_required([])
  end

  defp normalize_client_url(changeset) do
    case get_change(changeset, :client_url) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :client_url, @default_client_url)

      url when is_binary(url) ->
        put_change(changeset, :client_url, url |> String.trim() |> String.trim_trailing("/"))

      _ ->
        changeset
    end
  end
end
