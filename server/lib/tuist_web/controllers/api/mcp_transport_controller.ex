defmodule TuistWeb.API.MCPTransportController do
  use TuistWeb, :controller

  alias Boruta.Oauth.Token, as: OAuthToken
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.MCPServers.Transport
  alias Tuist.Accounts.User
  alias Tuist.FeatureFlags
  alias TuistWeb.Authentication

  def index(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case admitted(conn) do
      {:ok, user} -> json(conn, %{servers: Transport.connections(user), builtin_mcp_allowed: builtin_allowed?(conn)})
      _ -> error(conn, 403, :forbidden)
    end
  end

  def discover(conn, %{"server_id" => id, "endpoint" => endpoint}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with {:ok, user} <- admitted(conn),
         true <- valid_endpoint?(endpoint),
         {:ok, tools} <- Transport.discover(user, id, endpoint, fn -> authorized?(conn, user.id) end) do
      json(conn, %{tools: tools})
    else
      _ -> error(conn, 403, :mcp_unavailable)
    end
  end

  def discover(conn, _), do: error(conn, 400, :invalid_arguments)

  def invoke(conn, %{"server_id" => id}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with {:ok, user} <- admitted(conn),
         %{"endpoint" => endpoint, "name" => name, "arguments" => args} <- conn.body_params,
         true <- valid_endpoint?(endpoint),
         {:ok, result} <- Transport.call(user, id, endpoint, name, args, fn -> authorized?(conn, user.id) end) do
      json(conn, %{result: result})
    else
      {:error, :mcp_outcome_unknown} -> error(conn, 502, :mcp_outcome_unknown)
      _ -> error(conn, 403, :mcp_not_dispatched)
    end
  end

  defp admitted(conn) do
    with %User{id: id} <- Authentication.app_user(conn),
         %User{active: true, disabled_at: nil} = user <- Accounts.get_user_by_id(id),
         true <- FeatureFlags.luft_enabled?(user),
         do: {:ok, user}
  end

  defp authorized?(conn, id), do: match?({:ok, %User{id: ^id}}, admitted(conn))
  defp valid_endpoint?(endpoint), do: is_binary(endpoint) and Regex.match?(~r/\A[0-9a-f]{64}\z/, endpoint)

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
