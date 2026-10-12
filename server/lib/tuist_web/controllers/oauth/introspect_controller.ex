defmodule TuistWeb.Oauth.IntrospectController do
  use TuistWeb, :controller

  alias Boruta.Oauth.Authorization.Client
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.Request
  alias Tuist.Environment
  alias Tuist.Kura.SelfHostedClients
  alias Tuist.OAuth.Introspection

  def introspect(%Plug.Conn{} = conn, params) do
    # Self-hosted credentials (`cache_…`) are not UUIDs, which Boruta's request
    # parsing requires of a client id, so they are answered before it — through
    # it they could only ever 400.
    if SelfHostedClients.self_hosted_client_id?(params["client_id"]) do
      introspect_self_hosted(conn, params["client_id"], params["client_secret"], params["token"])
    else
      case Request.introspect_request(conn) do
        {:ok, request} ->
          if dedicated_kura_client?(request.client_id) do
            introspect_control_plane(conn, request)
          else
            introspect_self_hosted(
              conn,
              request.client_id,
              conn.params["client_secret"],
              request.token
            )
          end

        {:error, %Error{} = error} ->
          respond_error(conn, error)
      end
    end
  end

  # Tuist-operated control-plane client: trusted infrastructure, unconstrained.
  defp introspect_control_plane(conn, request) do
    case Client.authorize(
           id: request.client_id,
           source: request.client_authentication,
           grant_type: "introspect"
         ) do
      {:ok, _client} ->
        respond_introspection(conn, Introspection.token_response(request.token))

      {:error, %Error{} = error} ->
        respond_error(conn, error)
    end
  end

  # Customer self-hosted node: verify the tenant-scoped credential and constrain
  # the response to the credential's account, so a node can only introspect its
  # own tenant's tokens.
  defp introspect_self_hosted(conn, client_id, client_secret, token) when is_binary(token) do
    case SelfHostedClients.verify(client_id, client_secret) do
      {:ok, account} ->
        respond_introspection(conn, Introspection.token_response(token, account))

      :error ->
        invalid_client(conn)
    end
  end

  defp introspect_self_hosted(conn, _client_id, _client_secret, _token), do: invalid_client(conn)

  defp respond_introspection(conn, response) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(response)
  end

  defp respond_error(conn, %Error{} = error) do
    conn
    |> put_status(error.status)
    |> json(%{
      error: to_string(error.error),
      error_description: error.error_description
    })
  end

  defp dedicated_kura_client?(client_id) do
    Environment.kura_control_plane_configured?() and
      client_id == Environment.kura_control_plane_client_id()
  end

  defp invalid_client(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: "invalid_client",
      error_description: "Invalid client_id or client_secret."
    })
  end
end
