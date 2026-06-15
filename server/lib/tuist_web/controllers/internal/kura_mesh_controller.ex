defmodule TuistWeb.Internal.KuraMeshController do
  use TuistWeb, :controller

  alias Boruta.BasicAuth
  alias Tuist.Kura.Mesh
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
