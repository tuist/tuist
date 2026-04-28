defmodule Tuist.VCS.GitHubAppInstallation do
  @moduledoc """
  A module that represents GitHub app installations for accounts.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @default_client_url "https://github.com"
  @default_api_url "https://api.github.com"

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
    |> validate_format(:client_url, ~r{^https?://[^\s]+$}, message: "must be a valid URL like https://github.example.com")
    |> unique_constraint([:account_id])
    |> unique_constraint([:installation_id])
    |> foreign_key_constraint(:account_id)
  end

  def update_changeset(github_app_installation, attrs) do
    github_app_installation
    |> cast(attrs, [:html_url])
    |> validate_required([])
  end

  @doc """
  Returns the default client URL used when no GitHub Enterprise Server is configured.
  """
  def default_client_url, do: @default_client_url

  @doc """
  Computes the REST API base URL for a given client URL. github.com uses
  the dedicated `api.github.com` host; GitHub Enterprise Server installs
  expose the API under `/api/v3` on the same host.
  """
  def api_url(client_url \\ @default_client_url)
  def api_url(@default_client_url), do: @default_api_url
  def api_url(nil), do: @default_api_url

  def api_url(client_url) when is_binary(client_url) do
    client_url |> String.trim_trailing("/") |> Kernel.<>("/api/v3")
  end

  @doc """
  Returns the API base URL for a `%GitHubAppInstallation{}` struct or any
  map that has a `client_url`.
  """
  def installation_api_url(%__MODULE__{client_url: client_url}), do: api_url(client_url)
  def installation_api_url(%{client_url: client_url}), do: api_url(client_url)
  def installation_api_url(_), do: @default_api_url

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
