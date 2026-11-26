defmodule LuftServerWeb.MCPServersController do
  @moduledoc """
  MCP servers (`LuftServer.MCPServers`): a person's own under `/api/me`, and
  an organization's under `/api/accounts/:account_handle`, which every member
  can list and only admins (Tuist's account-update permission) can change.
  Responses are metadata only and never cached; no credential is returned.

  Signing in to a server goes through the app, the same way signing in to
  Luft does: the authorization server returns to `callback/2`, which hands the
  result to `luft://mcp-callback`, and the app posts it to `complete/2` with
  the person's bearer token. A sign-in therefore completes only for the
  people who may act for the server's owner.
  """
  use LuftServerWeb, :controller

  alias LuftServer.Config
  alias LuftServer.MCPServers
  alias LuftServer.Tuist.Scope

  plug LuftServerWeb.Plugs.RequireLuftAccess when action != :callback

  def index(conn, params) do
    with {:ok, owner} <- owner(conn, params, :read) do
      json(conn, %{servers: Enum.map(MCPServers.list(owner), &summary/1)})
    end
  end

  def create(conn, params) do
    with {:ok, owner} <- owner(conn, params, :write) do
      case MCPServers.add(owner, params) do
        {:ok, server} -> json(conn, %{server: summary(server)})
        {:error, reason} -> error(conn, reason)
      end
    end
  end

  def delete(conn, %{"id" => id} = params) do
    with {:ok, owner} <- owner(conn, params, :write) do
      :ok = MCPServers.remove(owner, id)
      send_resp(conn, 204, "")
    end
  end

  def authorize(conn, %{"id" => id} = params) do
    with {:ok, owner} <- owner(conn, params, :write) do
      case MCPServers.start_authorization(owner, id, redirect_uri()) do
        {:ok, url} -> json(conn, %{url: url})
        {:error, reason} -> error(conn, reason)
      end
    end
  end

  def complete(conn, params) do
    with {:ok, owner} <- owner(conn, params, :write) do
      case MCPServers.complete_authorization(
             [owner],
             Map.take(conn.body_params, ~w(state code iss))
           ) do
        {:ok, server} -> json(conn, %{server: summary(server)})
        {:error, reason} -> error(conn, reason)
      end
    end
  end

  @doc "Hands the authorization server's answer to the app, unchanged and unread."
  def callback(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> redirect(external: "luft://mcp-callback?" <> conn.query_string)
  end

  defp redirect_uri, do: Config.public_url() <> "/mcp-servers/callback"

  defp owner(conn, %{"account_handle" => handle}, access) do
    session = conn.assigns.session

    case Scope.load(session, handle) do
      {:ok, %Scope{organization_id: id} = scope} when is_integer(id) ->
        if access == :read or scope.can_create_threads,
          do: {:ok, MCPServers.owner(:account, scope.account_id)},
          else: error(conn, :forbidden)

      {:ok, _personal} ->
        error(conn, :not_found)

      {:error, :unauthorized} ->
        error(conn, :unauthorized)

      {:error, :not_found} ->
        error(conn, :not_found)

      {:error, _reason} ->
        error(conn, :tuist_unavailable)
    end
  end

  defp owner(conn, _params, _access),
    do: {:ok, MCPServers.owner(:user, conn.assigns.session.user_sub)}

  defp summary(server) do
    %{
      id: server.id,
      name: server.name,
      url: server.url,
      connected: Map.get(server, :connected, not is_nil(Map.get(server, :access_token))),
      updated_at: server.updated_at
    }
  end

  defp error(conn, reason) do
    {status, message} = error_response(reason)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{code: reason, message: message})
  end

  defp error_response(:unauthorized), do: {:unauthorized, "Sign in again."}
  defp error_response(:forbidden), do: {:forbidden, "Only organization admins can do this."}
  defp error_response(:not_found), do: {:not_found, "Not found."}
  defp error_response(:invalid_url), do: {:unprocessable_entity, "Enter the server's HTTPS URL."}

  defp error_response(:invalid_name),
    do: {:unprocessable_entity, "Enter a name up to 64 characters."}

  defp error_response(:too_many_servers),
    do: {:unprocessable_entity, "You can add up to 25 servers."}

  defp error_response(:rate_limited),
    do: {:too_many_requests, "Too many sign-ins to this server. Try again in a few minutes."}

  defp error_response(:access_denied), do: {:unprocessable_entity, "The sign-in was cancelled."}

  defp error_response(reason) when reason in [:oauth_not_supported, :registration_not_supported],
    do: {:unprocessable_entity, "This server doesn't support signing in from Luft."}

  defp error_response(:tuist_unavailable),
    do: {:service_unavailable, "Tuist could not be reached. Try again."}

  defp error_response(:storage_unavailable), do: {:service_unavailable, "Try again."}

  defp error_response(_reason),
    do: {:bad_gateway, "The sign-in did not complete. Try again."}
end
