defmodule TuistWeb.Internal.KuraUsageController do
  use TuistWeb, :controller

  alias Boruta.BasicAuth
  alias Boruta.Oauth.Authorization.Client
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.SelfHostedClients
  alias Tuist.Kura.Usage

  def create(conn, %{"schema_version" => 1, "events" => events}) when is_list(events) do
    case authorize(conn) do
      {:ok, :unconstrained} ->
        ingest(conn, events)

      {:ok, {:account, account}} ->
        if events_scoped_to_account?(events, account) do
          ingest(conn, events)
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
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload"})
  end

  defp ingest(conn, events) do
    case Usage.create_events(events) do
      {:ok, count} ->
        conn
        |> put_status(:accepted)
        |> json(%{accepted: count})

      {:error, :too_many_events} ->
        conn
        |> put_status(:payload_too_large)
        |> json(%{error: "too_many_events"})
    end
  end

  # A self-hosted credential may only report usage for its own tenant. Rejecting
  # the whole batch on any foreign `tenant_id` keeps a customer's node from
  # attributing traffic to another account.
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
