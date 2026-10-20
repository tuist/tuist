defmodule AtlasWeb.Plugs.MCPAuth do
  @moduledoc """
  Resolves the bearer token on MCP requests to an `Atlas.Users.User` and
  assigns it as `:current_user`. On missing or invalid tokens, responds
  with a 401 and a `www-authenticate` header pointing at the OAuth
  protected-resource metadata endpoint so MCP clients can discover the
  authorization server.
  """

  import Plug.Conn

  alias Atlas.Guardian
  alias AtlasWeb.RequestOrigin

  @resource_metadata_path "/.well-known/oauth-protected-resource/mcp"

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_token(conn) do
      {:ok, token} ->
        case Guardian.resource_from_token(token) do
          {:ok, user, claims} ->
            conn
            |> assign(:current_user, user)
            |> assign(:mcp_claims, claims)

          _ ->
            unauthorized(conn)
        end

      :error ->
        unauthorized(conn)
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, token}
      ["bearer " <> token | _] -> {:ok, token}
      _ -> :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer realm="atlas-mcp", resource_metadata="#{RequestOrigin.from_conn(conn)}#{@resource_metadata_path}")
    )
    |> put_resp_content_type("application/json")
    |> send_resp(
      401,
      JSON.encode!(%{error: "invalid_token", error_description: "Missing or invalid access token."})
    )
    |> halt()
  end
end
