defmodule Tuist.Kura.Registrations do
  @moduledoc """
  Lease-based registration of customer-owned Kura cache endpoints.

  A self-hosted node posts a registration heartbeat (its `node_id`, client-facing
  `advertised_http_url`, readiness, and runtime metadata). Each heartbeat refreshes
  the node's lease; endpoint lookup only returns ready, non-expired endpoints, so a
  node that stops heartbeating drops out on its own. The control plane never calls
  the node — the outbound heartbeat is the only health signal.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Kura.RegisteredEndpoint
  alias Tuist.Repo

  # Heartbeat cadence and lease the control plane advertises back to the node.
  # The lease is several missed heartbeats wide so a single dropped POST does not
  # flap an endpoint out of rotation.
  @heartbeat_interval_seconds 60
  @lease_seconds 180

  def heartbeat_interval_seconds, do: @heartbeat_interval_seconds
  def lease_seconds, do: @lease_seconds

  @doc """
  Records a registration heartbeat for `account`, keyed by `node_id`. Refreshes
  the lease (`last_heartbeat_at` / `expires_at`) and the advertised endpoint and
  runtime metadata. Returns `{:ok, endpoint}` or `{:error, changeset}`.
  """
  def register_heartbeat(%Account{} = account, attrs) do
    now = now()

    params =
      attrs
      |> Map.put(:account_id, account.id)
      |> Map.put(:last_heartbeat_at, now)
      |> Map.put(:expires_at, DateTime.add(now, @lease_seconds, :second))

    case_result =
      case fetch_by_node_id(account, attrs[:node_id] || attrs["node_id"]) do
        nil -> %RegisteredEndpoint{}
        existing -> existing
      end

    case_result
    |> RegisteredEndpoint.changeset(params)
    |> Repo.insert_or_update()
  end

  @doc """
  Client-facing URLs for `account`'s currently advertisable registered endpoints:
  ready, lease not yet expired. Deduplicated by URL so a customer can heartbeat
  every pod while still exposing a single load balancer.
  """
  def active_advertised_urls(%Account{} = account) do
    account
    |> active_query()
    |> select([e], e.advertised_http_url)
    |> distinct(true)
    |> Repo.all()
  end

  @doc "All registered endpoints for `account` (for the account/ops UI), newest heartbeat first."
  def list_endpoints(%Account{} = account) do
    Repo.all(from(e in RegisteredEndpoint, where: e.account_id == ^account.id, order_by: [desc: e.last_heartbeat_at]))
  end

  @doc "Deletes registered endpoints whose lease has lapsed. Safe to run from a periodic sweeper."
  def delete_expired(now \\ now()) do
    {count, _} = Repo.delete_all(from(e in RegisteredEndpoint, where: e.expires_at <= ^now))

    count
  end

  defp active_query(%Account{} = account) do
    from(e in RegisteredEndpoint,
      where: e.account_id == ^account.id and e.ready == true and e.expires_at > ^now()
    )
  end

  defp fetch_by_node_id(_account, nil), do: nil

  defp fetch_by_node_id(%Account{} = account, node_id) do
    Repo.get_by(RegisteredEndpoint, account_id: account.id, node_id: node_id)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
