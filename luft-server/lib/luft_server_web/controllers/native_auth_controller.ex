defmodule LuftServerWeb.NativeAuthController do
  @moduledoc "Public native OAuth authorization and token endpoints."
  use LuftServerWeb, :controller

  alias LuftServer.NativeAuth
  alias LuftServer.Sessions
  alias LuftServer.Tuist.OIDC

  def discovery(conn, _params), do: json(conn, %{luft_oauth_client_id: NativeAuth.client_id()})

  def apple(conn, params), do: authorize(conn, params, "apple")
  def google(conn, params), do: authorize(conn, params, "google")
  def github(conn, params), do: authorize(conn, params, "github")

  def authorize(conn, params) do
    authorize(conn, params, nil)
  end

  defp authorize(conn, params, provider) do
    with {:ok, request} <- NativeAuth.validate_request(params),
         {:ok, pending} <- Sessions.reserve_native_transaction(),
         transaction =
           OIDC.new_transaction()
           |> Map.put("native", request)
           |> Map.put("native_pending", pending),
         {:ok, url} <- OIDC.authorization_url(transaction, provider: provider) do
      conn |> put_session(:signin, transaction) |> redirect(external: url)
    else
      {:error, :invalid_request} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})

      _ ->
        conn |> put_status(:service_unavailable) |> json(%{error: "tuist_unavailable"})
    end
  end

  def token(conn, _params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")

    case NativeAuth.exchange(conn) do
      {:ok, credentials} ->
        json(conn, credentials)

      {:error, :invalid_request} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})

      {:error, _} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_grant"})
    end
  end
end
