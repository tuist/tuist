defmodule Tuist.VCS.GitHubAppInstallation do
  @moduledoc """
  A `GitHubAppInstallation` represents an account's connection to a GitHub
  App installation. For github.com (the default `client_url`), the App's
  credentials live in environment variables and the installation row only
  carries the `installation_id` GitHub assigned at install time. For
  GitHub Enterprise Server (a custom `client_url`), the row also stores
  per-installation App credentials (`app_id`, `client_id`, `client_secret`,
  `private_key`, `webhook_secret`) registered through GitHub's App
  manifest flow.

  `installation_id` is `nil` while a manifest-flow registration is pending
  (the customer has registered the App on their GHES instance but has not
  yet installed it); the setup callback fills it in.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary
  alias Tuist.VCS

  @default_client_url "https://github.com"

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "github_app_installations" do
    field :installation_id, :string
    field :html_url, :string
    field :client_url, :string, default: @default_client_url

    field :app_id, :string
    field :app_slug, :string
    field :client_id, :string
    field :client_secret, Binary
    field :private_key, Binary
    field :webhook_secret, Binary

    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :account_id,
    :installation_id,
    :html_url,
    :client_url,
    :app_id,
    :app_slug,
    :client_id,
    :client_secret,
    :private_key,
    :webhook_secret
  ]

  def changeset(github_app_installation \\ %__MODULE__{}, attrs) do
    github_app_installation
    |> cast(attrs, @cast_fields)
    |> normalize_client_url()
    |> validate_required([:account_id, :client_url])
    |> validate_install_state()
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

  # A row is valid if it carries either an installation_id (post-install
  # state) or a private_key (pending manifest-flow registration). Both
  # together is also fine — that's the steady state for a GHES install.
  defp validate_install_state(changeset) do
    has_installation_id? = field_present?(changeset, :installation_id)
    has_private_key? = field_present?(changeset, :private_key)

    if has_installation_id? or has_private_key? do
      changeset
    else
      add_error(changeset, :installation_id, "can't be blank")
    end
  end

  defp field_present?(changeset, field) do
    case get_field(changeset, field) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  def update_changeset(github_app_installation, attrs) do
    github_app_installation
    |> cast(attrs, [:html_url, :installation_id, :app_slug])
    |> validate_required([])
    |> unique_constraint([:installation_id])
  end

  @doc """
  Returns true if the installation carries its own App credentials
  (manifest-flow registered) instead of relying on the global env vars.
  """
  def has_own_app_credentials?(%__MODULE__{app_id: app_id, private_key: pk}) when is_binary(app_id) and is_binary(pk),
    do: true

  def has_own_app_credentials?(_), do: false

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
