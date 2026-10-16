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

  defp redirect_uri(conn, %Server{} = server), do: redirect_uri(conn, server.name)

  defp redirect_uri(conn, server_name) do
    url(conn, ~p"/mcps/#{server_name}/callback")
  end
end
