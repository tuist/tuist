defmodule AtlasWeb.Oauth.TokenController do
  @behaviour Boruta.Oauth.TokenApplication

  use AtlasWeb, :controller

  alias Boruta.Oauth
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.TokenApplication
  alias Boruta.Oauth.TokenResponse

  # Boruta resolves `request` (an unsigned JWT merged into the parameters) and
  # `request_uri` (fetched over HTTP) from the query or body before it
  # authenticates the client, so an anonymous caller could make Atlas request
  # arbitrary URLs. No supported client uses either.
  def token(%Plug.Conn{query_params: query_params, body_params: body_params} = conn, _params)
      when is_map_key(query_params, "request") or is_map_key(query_params, "request_uri") or
             is_map_key(body_params, "request") or is_map_key(body_params, "request_uri") do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_request", error_description: "request and request_uri are not supported."})
  end

  def token(%Plug.Conn{} = conn, _params), do: Oauth.token(conn, __MODULE__)

  @impl TokenApplication
  def token_success(conn, %TokenResponse{} = response) do
    body =
      %{
        token_type: response.token_type,
        access_token: response.access_token,
        expires_in: response.expires_in,
        refresh_token: response.refresh_token,
        id_token: response.id_token
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(body)
  end

  @impl TokenApplication
  def token_error(conn, %Error{status: status, error: error, error_description: description}) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end
end
