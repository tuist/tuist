defmodule TuistWeb.Oauth.TokenController do
  @behaviour Boruta.Oauth.RevokeApplication
  @behaviour Boruta.Oauth.TokenApplication

  use TuistWeb, :controller

  alias Boruta.Oauth.Error
  alias Boruta.Oauth.RevokeApplication
  alias Boruta.Oauth.TokenApplication
  alias Boruta.Oauth.TokenResponse
  alias Tuist.Accounts
  alias Tuist.Environment

  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @claim_grant "urn:workos:agent-auth:grant-type:claim"

  def oauth_module, do: Application.get_env(:tuist, :oauth_module, Boruta.Oauth)

  def token(%Plug.Conn{} = conn, %{"grant_type" => @jwt_bearer_grant, "assertion" => assertion} = params) do
    case Accounts.exchange_protocol_agent_assertion(
           assertion,
           Environment.app_url(route_type: :app),
           Map.get(params, "resource")
         ) do
      {:ok, response} -> oauth_json(conn, response)
      {:error, :invalid_target} -> oauth_error(conn, "invalid_target", "The requested resource is not supported.")
      {:error, _reason} -> oauth_error(conn, "invalid_grant", "The identity assertion is invalid or expired.")
    end
  end

  def token(%Plug.Conn{} = conn, %{"grant_type" => @jwt_bearer_grant}) do
    oauth_error(conn, "invalid_request", "assertion is required.")
  end

  def token(%Plug.Conn{} = conn, %{"grant_type" => @claim_grant, "claim_token" => claim_token}) do
    case Accounts.poll_protocol_agent_claim(claim_token, Environment.app_url(route_type: :app)) do
      {:ok, response} ->
        oauth_json(conn, response)

      {:error, :authorization_pending} ->
        oauth_error(conn, "authorization_pending", "The user has not completed the claim ceremony.")

      {:error, :slow_down} ->
        oauth_error(conn, "slow_down", "The claim endpoint is being polled too quickly.")

      {:error, _reason} ->
        oauth_error(conn, "expired_token", "The claim token or user-code window has expired.")
    end
  end

  def token(%Plug.Conn{} = conn, %{"grant_type" => @claim_grant}) do
    oauth_error(conn, "invalid_request", "claim_token is required.")
  end

  def token(%Plug.Conn{} = conn, _params) do
    oauth_module().token(conn, __MODULE__)
  end

  # Protocol agent credentials are public-client tokens with no client secret to
  # present, so they are revoked directly. Anything else is an authorization
  # server token backed by Boruta, which runs its own client checks.
  def revoke(%Plug.Conn{} = conn, %{"token" => token}) when is_binary(token) and token != "" do
    case Accounts.revoke_protocol_agent_access_token(token) do
      :ok ->
        conn
        |> put_resp_header("pragma", "no-cache")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(:ok, "")

      :not_found ->
        oauth_module().revoke(conn, __MODULE__)
    end
  end

  def revoke(%Plug.Conn{} = conn, _params) do
    oauth_error(conn, "invalid_request", "token is required.")
  end

  @impl TokenApplication
  def token_success(conn, %TokenResponse{} = response) do
    token_data =
      %{
        token_type: response.token_type,
        access_token: response.access_token,
        expires_in: response.expires_in,
        refresh_token: response.refresh_token,
        id_token: response.id_token
      }
      |> Enum.filter(fn {_key, value} -> value != nil end)
      |> Map.new()

    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(token_data)
  end

  @impl RevokeApplication
  def revoke_success(%Plug.Conn{} = conn) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(:ok, "")
  end

  @impl RevokeApplication
  def revoke_error(conn, %Error{status: status, error: error, error_description: error_description}) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end

  @impl TokenApplication
  def token_error(conn, %Error{status: status, error: error, error_description: error_description}) do
    conn
    |> put_status(status)
    |> json(%{
      error: error,
      error_description: error_description
    })
  end

  defp oauth_json(conn, response) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(response)
  end

  defp oauth_error(conn, error, description) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:bad_request)
    |> json(%{error: error, error_description: description})
  end
end
