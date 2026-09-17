defmodule AtlasWeb.MCPOAuthController do
  use AtlasWeb, :controller

  alias Atlas.MCP
  alias Atlas.MCP.OAuth
  alias Atlas.MCP.Proxy.Server

  def authorize(conn, %{"server_name" => server_name} = params) do
    with {:ok, %Server{} = server} <- MCP.get_server(server_name),
         {:ok, url} <-
           OAuth.authorization_url(
             server,
             conn.assigns.current_user,
             redirect_uri(conn, server),
             params["return_to"] || ~p"/admin/mcps"
           ) do
      redirect(conn, external: url)
    else
      {:error, :unsupported_auth_type} ->
        conn
        |> put_flash(:error, "This MCP server does not use OAuth.")
        |> redirect(to: ~p"/admin/mcps")

      _error ->
        conn
        |> put_flash(:error, "MCP server not found.")
        |> redirect(to: ~p"/admin/mcps")
    end
  end

  def callback(conn, %{"server_name" => server_name} = params) do
    case OAuth.handle_callback(conn.assigns.current_user, server_name, params, redirect_uri(conn, server_name)) do
      {:ok, _session, return_to} ->
        conn
        |> put_flash(:info, "MCP server connected.")
        |> redirect(to: return_to)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not connect MCP server.")
        |> redirect(to: ~p"/admin/mcps")
    end
  end

  @doc """
  Receives an operator grant handed back by ops.tuist.dev.

  Ops appends the token to `return_to` and redirects; it never renders it, so
  there is nothing for a person to copy and nothing to paste. Taking the
  redirect keeps the bearer out of clipboards and conversations — it is stored
  and the URL is immediately replaced, so it does not linger in history, a
  `Referer`, or anything that logs a query string.
  """
  def operator_grant(conn, %{"server_name" => server_name, "operator_grant" => token, "state" => state}) do
    user = conn.assigns.current_user

    with {:ok, request} <- MCP.consume_operator_grant_request(user, server_name, state),
         {:ok, grant} <-
           MCP.put_operator_grant(user, server_name, token,
             interface: "dashboard",
             expected_account_handle: request.account_handle
           ) do
      conn
      |> put_flash(:info, "Operator grant stored for #{grant.account_handle}.")
      |> redirect(to: ~p"/admin/mcps")
    else
      {:error, :unknown_request} ->
        conn
        |> put_flash(:error, "That grant did not come from a request you started.")
        |> redirect(to: ~p"/admin/mcps")

      {:error, :expired_request} ->
        conn
        |> put_flash(:error, "That access request expired. Start it again.")
        |> redirect(to: ~p"/admin/mcps")

      {:error, :unreadable_grant} ->
        conn
        |> put_flash(:error, "That grant could not be read.")
        |> redirect(to: ~p"/admin/mcps")

      {:error, {:unsupported_grant_tier, tier}} ->
        conn
        |> put_flash(:error, "Atlas proxies read grants only; that grant is #{tier}.")
        |> redirect(to: ~p"/admin/mcps")

      {:error, {:account_mismatch, requested}} ->
        conn
        |> put_flash(:error, "That grant is not for #{requested}.")
        |> redirect(to: ~p"/admin/mcps")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not store the operator grant.")
        |> redirect(to: ~p"/admin/mcps")
    end
  end

  def operator_grant(conn, _params) do
    conn
    |> put_flash(:error, "No operator grant in the response from ops.")
    |> redirect(to: ~p"/admin/mcps")
  end

  defp redirect_uri(conn, %Server{} = server), do: redirect_uri(conn, server.name)

  defp redirect_uri(conn, server_name) do
    url(conn, ~p"/mcps/#{server_name}/callback")
  end
end
