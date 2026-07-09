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
    # `kura_self_hosted_peer` is an enrolled node's internal peer (mTLS) URL,
    # used only for mesh discovery and never returned to the CLI as a cache
    # endpoint. Self-hosted client-facing URLs are not stored here: each node
    # self-registers its advertised URL via heartbeats.
    field :technology, Ecto.Enum,
      values: [default: 0, kura: 1, kura_self_hosted_peer: 3],
      default: :default

    # Set when a `kura_self_hosted_peer` row's node stops proving liveness: the
    # peer is withheld from the mesh but the row (and its full peer URL, which
    # heartbeats don't carry) is kept so a heartbeat from the returning node
    # reactivates it without re-enrollment.
    field :deactivated_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(endpoint \\ %__MODULE__{}, attrs) do
    endpoint
    |> cast(attrs, [:url, :account_id, :technology])
    |> validate_required([:url, :account_id, :technology])
    |> validate_url(:url)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :technology, :url], message: "has already been added")
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
