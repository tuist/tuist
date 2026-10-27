defmodule Tuist.Kura.RegisteredEndpoint do
  @moduledoc """
  A client-facing Kura cache endpoint a customer-owned node reports via
  registration heartbeats.

  Distinct from `Tuist.Kura.Server` (Tuist-provisioned managed Kura) and from
  the static `account_cache_endpoints` rows: a registered endpoint is leased.
  Each heartbeat refreshes `last_heartbeat_at`/`expires_at`; once a node stops
  heartbeating the lease lapses and endpoint lookup stops advertising it, so a
  dead customer node disappears on its own without Tuist probing it.

  `advertised_http_url` is the node's client-facing HTTP cache URL (what the CLI
  hits), deliberately separate from the internal peer URL (`KURA_NODE_URL`,
  the mTLS replication port).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_registered_endpoints" do
    field :node_id, :string
    field :region, :string
    field :advertised_http_url, :string
    field :ready, :boolean, default: false
    field :version, :string
    field :traffic_state, :string
    field :last_heartbeat_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @castable [
    :account_id,
    :node_id,
    :region,
    :advertised_http_url,
    :ready,
    :version,
    :traffic_state,
    :last_heartbeat_at,
    :expires_at
  ]

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @castable)
    |> validate_required([:account_id, :node_id, :advertised_http_url, :last_heartbeat_at, :expires_at])
    |> validate_advertised_http_url()
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :node_id])
  end

  defp validate_advertised_http_url(changeset) do
    validate_change(changeset, :advertised_http_url, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host, userinfo: nil}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [advertised_http_url: "must be a valid http or https URL without embedded credentials"]
      end
    end)
  end
end
