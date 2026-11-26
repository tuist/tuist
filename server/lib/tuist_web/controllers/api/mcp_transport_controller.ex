defmodule TuistWeb.API.MCPTransportController do
  @moduledoc """
  Tells Luft whether a session may use Tuist's own MCP tools: only a grant
  that actually holds the `mcp` scope does. MCP servers people connect are
  kept by Luft.
  """
  use TuistWeb, :controller

  alias Boruta.Oauth.Token, as: OAuthToken
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.FeatureFlags
  alias TuistWeb.Authentication

  def index(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case admitted(conn) do
      # MCP servers live in Luft now; `servers` stays empty for Luft replicas
      # that still read it.
      {:ok, _user} -> json(conn, %{servers: [], builtin_mcp_allowed: builtin_allowed?(conn)})
      _ -> error(conn, 403, :forbidden)
    end
  end

  defp admitted(conn) do
    with %User{id: id} <- Authentication.app_user(conn),
         %User{active: true, disabled_at: nil} = user <- Accounts.get_user_by_id(id),
         true <- FeatureFlags.luft_enabled?(user),
         do: {:ok, user}
  end

  # A personal app grant is not an MCP grant. Never offer built-ins just
  # because app_user associates an OAuth credential with a person.
  defp builtin_allowed?(conn) do
    case Authentication.authenticated_subject(conn) do
      %User{} ->
        true

      %AuthenticatedAccount{scopes: scopes} ->
        with true <- AccountToken.mcp_scope() in scopes,
             ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
             %OAuthToken{scope: scope} = grant <- Boruta.AccessTokensAdapter.get_by(value: bearer),
             :ok <- OAuthToken.ensure_valid(grant) do
          AccountToken.mcp_scope() in String.split(scope || "", " ", trim: true)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp error(conn, status, category),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_status(status)
      |> json(%{error: %{code: Atom.to_string(category)}})
end
