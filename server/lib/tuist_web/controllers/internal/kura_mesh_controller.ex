defmodule TuistWeb.Internal.KuraMeshController do
  use TuistWeb, :controller

  alias Boruta.BasicAuth
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
              peers: enrollment.peers
            })

          {:error, reason} when reason in [:invalid_csr, :invalid_node_url] ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: to_string(reason)})
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

  # Registration heartbeat: a self-hosted node periodically reports its
  # client-facing endpoint and liveness. The lease (see the response) is
  # refreshed on each heartbeat; lookup drops endpoints whose lease lapses, so a
  # node that stops heartbeating disappears without the control plane probing it.
  def register(conn, %{"node_id" => node_id, "advertised_http_url" => advertised_http_url} = params)
      when is_binary(node_id) and is_binary(advertised_http_url) do
    case authorize(conn) do
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
         {:ok, account} <- SelfHostedClients.verify(client_id, client_secret) do
      {:ok, account}
    else
      _ -> {:error, :unauthorized}
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
end
