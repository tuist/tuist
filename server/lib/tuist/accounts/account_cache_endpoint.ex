defmodule Tuist.Accounts.AccountCacheEndpoint do
  @moduledoc """
  Schema for custom cache endpoints configured at the account level.
  Organizations can configure one or more cache endpoint URLs that will be used
  instead of the default Tuist-hosted endpoints.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "account_cache_endpoints" do
    field :url, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(endpoint \\ %__MODULE__{}, attrs) do
    endpoint
    |> cast(attrs, [:url, :account_id])
    |> validate_required([:url, :account_id])
    |> validate_url(:url)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :url], message: "has already been added")
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid HTTP or HTTPS URL"}]
      end
    end)
  end
end
