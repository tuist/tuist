defmodule TuistWeb.Oauth.IntrospectController do
  use TuistWeb, :controller

  alias Boruta.Oauth.Authorization.Client
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.Request
  alias Tuist.OAuth.Introspection

  def introspect(%Plug.Conn{} = conn, _params) do
    with {:ok, request} <- Request.introspect_request(conn),
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
    end
  end
end
