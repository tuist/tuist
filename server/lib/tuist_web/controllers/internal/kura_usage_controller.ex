defmodule TuistWeb.Internal.KuraUsageController do
  use TuistWeb, :controller

  alias Boruta.BasicAuth
  alias Boruta.Oauth.Authorization.Client
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.SelfHostedClients
  alias Tuist.Kura.StorageTelemetry
  alias Tuist.Kura.Usage

  def create(conn, %{"schema_version" => 1, "events" => events} = params) when is_list(events) do
    with {:ok, evictions} <- optional_list(params, "evictions"),
         {:ok, storage_snapshots} <- optional_list(params, "storage_snapshots") do
      case authorize(conn) do
        {:ok, :unconstrained} ->
          ingest(conn, events, evictions, storage_snapshots)

        {:ok, {:account, account}} ->
          if events_scoped_to_account?(events ++ evictions ++ storage_snapshots, account) do
            # Storage telemetry from a self-hosted credential is discarded, not
            # persisted: every field in it (region included) is
            # customer-controlled, while claim sizing reads the tables as
            # trusted managed-node signal. Persisting it would let a
            # self-hosted node claiming a governed region resize the account's
            # hosted claim. Usage still ingests, so a node that sends both
            # keeps its metering.
            ingest(conn, events, [], [])
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "tenant_mismatch"})
          end

        {:error, :unauthorized} ->
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "unauthorized"})
      end
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_payload"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload"})
  end

  # Nodes that predate storage telemetry send batches without these keys, so
  # absence is an empty list rather than an error.
  defp optional_list(params, key) do
    case Map.get(params, key, []) do
      list when is_list(list) -> {:ok, list}
      _other -> :error
    end
  end

  defp ingest(conn, events, evictions, storage_snapshots) do
    with {:ok, count} <- Usage.create_events(events),
         {:ok, _evictions} <- StorageTelemetry.create_eviction_events(evictions),
         {:ok, _snapshots} <- StorageTelemetry.create_storage_snapshots(storage_snapshots) do
      conn
      |> put_status(:accepted)
      |> json(%{accepted: count})
    else
      {:error, :too_many_events} ->
        conn
        |> put_status(:payload_too_large)
        |> json(%{error: "too_many_events"})
    end
  end

  # A self-hosted credential may only report usage for its own tenant. Rejecting
  # the whole batch on any foreign `tenant_id` keeps a customer's node from
  # attributing traffic or storage telemetry to another account.
  defp events_scoped_to_account?(events, %Account{name: name}) do
    handle = String.downcase(name)
    Enum.all?(events, &(String.downcase(to_string(&1["tenant_id"])) == handle))
  end

  # Mirrors the IntrospectController split: the Tuist-operated control-plane
  # client authorizes through Boruta and ingests unconstrained; a customer
  # self-hosted credential is verified locally and constrained to its account.
  defp authorize(conn) do
    case basic_credentials(conn) do
      {:ok, client_id, client_secret} ->
        if dedicated_kura_client?(client_id) do
          authorize_control_plane(client_id, client_secret)
        else
          authorize_self_hosted(client_id, client_secret)
        end

      {:error, :missing_credentials} ->
        {:error, :unauthorized}
    end
  end

  defp authorize_control_plane(client_id, client_secret) do
    case Client.authorize(
           id: client_id,
           source: %{type: "basic", value: client_secret},
           grant_type: "kura_usage"
         ) do
      {:ok, _client} -> {:ok, :unconstrained}
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_self_hosted(client_id, client_secret) do
    case SelfHostedClients.verify(client_id, client_secret) do
      {:ok, account} -> {:ok, {:account, account}}
      :error -> {:error, :unauthorized}
    end
  end

  defp basic_credentials(conn) do
    with [header | _] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, [client_id, client_secret]} <- BasicAuth.decode(header) do
      {:ok, client_id, client_secret}
    else
      _ -> {:error, :missing_credentials}
    end
  end

  defp dedicated_kura_client?(client_id) do
    Environment.kura_control_plane_configured?() and
      client_id == Environment.kura_control_plane_client_id()
  end
end
