defmodule TuistWeb.Internal.KuraMeshController do
  use TuistWeb, :controller

  alias Boruta.BasicAuth
  alias Boruta.Oauth.Authorization.Client
  alias Tuist.Accounts
  alias Tuist.Billing.Entitlements
  alias Tuist.Environment
  alias Tuist.Kura.Mesh
  alias Tuist.Kura.Registrations
  alias Tuist.Kura.SelfHostedClients

  # Node enrollment: a self-hosted node presents its tenant-scoped credential
  # (HTTP Basic) and a CSR, and gets back its signed certificate, the account
  # CA, the tenant id, and the peer list. This is the onboarding primitive that
  # lets a node self-configure with nothing but its credential and URL.
  def enroll(conn, %{"csr" => csr, "node_url" => node_url}) when is_binary(csr) and is_binary(node_url) do
    case authorize(conn) do
      {:ok, account} ->
        case Mesh.enroll_node(account, %{csr: csr, node_url: node_url}) do
          {:ok, enrollment} ->
            conn
            |> put_status(:created)
            |> json(%{
              tenant_id: enrollment.tenant_id,
              certificate: enrollment.certificate_pem,
              ca_certificate: enrollment.ca_certificate_pem,
              not_after: enrollment.not_after,
              renew_after_seconds: enrollment.renew_after_seconds,
              peers: enrollment.peers,
              managed_peers: enrollment.managed_peers
            })

          {:error, reason} when reason in [:invalid_csr, :invalid_node_url] ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: to_string(reason)})

          {:error, :ca_unavailable} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{error: "ca_unavailable"})
        end

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
    end
  end

  def enroll(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload"})
  end

  # Mesh heartbeat: an enrolled node periodically proves it is still a live
  # mesh member. Independent from the registration heartbeat (which advertises
  # the node's client-facing endpoint): this one keeps the node's mesh
  # membership from being swept as stale, reactivates it if it already was,
  # and returns the current peer list so peers refresh at heartbeat cadence
  # rather than at certificate renewal.
  def heartbeat(conn, %{"node_url" => node_url}) when is_binary(node_url) do
    case authorize(conn) do
      {:ok, account} ->
        view = Mesh.heartbeat_node(account, node_url)

        json(conn, %{
          mesh_member: view.mesh_member,
          peers: view.peers,
          heartbeat_interval_seconds: Mesh.mesh_heartbeat_interval_seconds()
        })

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
    end
  end

  def heartbeat(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload"})
  end

  # Peers-only read for managed pods: they don't enroll (Kubernetes owns their
  # liveness and their identity is controller-minted), so they must not enter
  # the membership/reactivation state machine — but they consume the same
  # dynamic peer view so a self-hosted peer joining or leaving propagates at
  # heartbeat cadence instead of through a fleet roll. Accepts the
  # deployment-level control-plane credential (with a tenant) or a self-hosted
  # client credential, like registration.
  def peers(conn, params) do
    case authorize_registration(conn, params) do
      {:ok, account} ->
        json(conn, %{
          peers: Mesh.self_hosted_peer_urls(account),
          refresh_interval_seconds: Mesh.mesh_heartbeat_interval_seconds()
        })

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
    end
  end

  # Registration heartbeat: a self-hosted node periodically reports its
  # client-facing endpoint and liveness. The lease (see the response) is
  # refreshed on each heartbeat; lookup drops endpoints whose lease lapses, so a
  # node that stops heartbeating disappears without the control plane probing it.
  def register(conn, %{"node_id" => node_id, "advertised_http_url" => advertised_http_url} = params)
      when is_binary(node_id) and is_binary(advertised_http_url) do
    case authorize_registration(conn, params) do
      {:ok, account} ->
        if tenant_mismatch?(params, account) do
          conn
          |> put_status(:conflict)
          |> json(%{error: "tenant_mismatch"})
        else
          register_heartbeat(conn, account, node_id, advertised_http_url, params)
        end

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
    end
  end

  def register(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload"})
  end

  defp register_heartbeat(conn, account, node_id, advertised_http_url, params) do
    attrs = %{
      node_id: node_id,
      advertised_http_url: advertised_http_url,
      region: params["region"],
      ready: params["ready"] == true,
      version: params["version"],
      traffic_state: params["traffic_state"]
    }

    case Registrations.register_heartbeat(account, attrs) do
      {:ok, endpoint} ->
        conn
        |> put_status(:ok)
        |> json(%{
          accepted: true,
          registration_id: endpoint.id,
          lease_seconds: Registrations.lease_seconds(),
          heartbeat_interval_seconds: Registrations.heartbeat_interval_seconds()
        })

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_registration"})
    end
  end

  defp tenant_mismatch?(%{"tenant_id" => tenant_id}, account) when is_binary(tenant_id) do
    String.downcase(tenant_id) != String.downcase(account.name)
  end

  defp tenant_mismatch?(_params, _account), do: false

  defp authorize(conn) do
    with {:ok, client_id, client_secret} <- basic_credentials(conn),
         {:ok, account} <- authorize_self_hosted(client_id, client_secret) do
      {:ok, account}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_registration(conn, params) do
    case basic_credentials(conn) do
      {:ok, client_id, client_secret} ->
        if dedicated_kura_client?(client_id) do
          authorize_control_plane_registration(client_id, client_secret, params)
        else
          authorize_self_hosted(client_id, client_secret)
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp authorize_control_plane_registration(client_id, client_secret, %{"tenant_id" => tenant_id})
       when is_binary(tenant_id) and tenant_id != "" do
    with {:ok, _client} <-
           Client.authorize(
             id: client_id,
             source: %{type: "basic", value: client_secret},
             grant_type: "kura_registration"
           ),
         %{} = account <- Accounts.get_account_by_handle(tenant_id),
         true <- Entitlements.allows?(account, :self_hosted_cache) do
      {:ok, account}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_control_plane_registration(_client_id, _client_secret, _params), do: {:error, :unauthorized}

  defp authorize_self_hosted(client_id, client_secret) do
    case SelfHostedClients.verify(client_id, client_secret) do
      {:ok, account} -> {:ok, account}
      :error -> {:error, :unauthorized}
    end
  end

  defp dedicated_kura_client?(client_id) do
    Environment.kura_control_plane_configured?() and
      client_id == Environment.kura_control_plane_client_id()
  end

  defp basic_credentials(conn) do
    with [header | _] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, [client_id, client_secret]} <- BasicAuth.decode(header) do
      {:ok, client_id, client_secret}
    else
      _ -> {:error, :missing_credentials}
    end
  end
end
