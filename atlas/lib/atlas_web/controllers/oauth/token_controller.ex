defmodule AtlasWeb.Oauth.TokenController do
  @behaviour Boruta.Oauth.TokenApplication

  use AtlasWeb, :controller

  alias Boruta.Oauth
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.TokenApplication
  alias Boruta.Oauth.TokenResponse

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
