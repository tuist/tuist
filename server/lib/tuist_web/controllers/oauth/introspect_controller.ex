defmodule TuistWeb.Oauth.IntrospectController do
  use TuistWeb, :controller

  alias Boruta.Oauth.Authorization.Client
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.Request
  alias Tuist.Environment
  alias Tuist.OAuth.Introspection

  def introspect(%Plug.Conn{} = conn, _params) do
    with {:ok, request} <- Request.introspect_request(conn),
         true <- dedicated_kura_client?(request.client_id),
         {:ok, _client} <-
           Client.authorize(
             id: request.client_id,
             source: request.client_authentication,
             grant_type: "introspect"
           ) do
      conn
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("cache-control", "no-store")
      |> json(Introspection.token_response(request.token))
    else
      {:error, %Error{} = error} ->
        conn
        |> put_status(error.status)
        |> json(%{
          error: to_string(error.error),
          error_description: error.error_description
        })

      false ->
        invalid_client(conn)
    end
  end

  defp dedicated_kura_client?(client_id) do
    Environment.kura_introspection_configured?() and
      client_id == Environment.kura_introspection_client_id()
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
