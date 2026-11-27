defmodule LuftServer.Workspaces.Preview do
  @moduledoc "A standalone, token-bound local preview API; never part of the public router."
  use Plug.Router

  alias LuftServer.Workspaces.Local
  alias LuftServer.Workspaces.MCP

  plug :authenticate

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    length: 65_536

  plug :match
  plug :dispatch

  get "/workspace" do
    reply(conn, Local.workspace(conn.private.workspace_connection))
  end

  post "/mcp" do
    MCP.call(
      conn,
      conn.private.workspace_connection,
      conn.private.workspace_mcp_actions
    )
  end

  match "/mcp" do
    conn |> put_resp_header("allow", "POST") |> send_resp(405, "Method not allowed")
  end

  post "/query" do
    reply(conn, Local.query(conn.private.workspace_connection, conn.body_params))
  end

  post "/action" do
    reply(conn, Local.action(conn.private.workspace_connection, conn.body_params))
  end

  match _ do
    reply(conn, {:error, %{code: "NOT_FOUND", message: "Preview endpoint not found"}})
  end

  def init(options), do: options

  def call(conn, options) do
    conn
    |> put_private(:workspace_connection, Keyword.fetch!(options, :connection))
    |> put_private(:workspace_token_hash, Keyword.fetch!(options, :token_hash))
    |> put_private(:workspace_mcp_actions, Keyword.get(options, :mcp_actions, []))
    |> super(options)
  end

  defp authenticate(conn, _) do
    expected = conn.private.workspace_token_hash

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        if Plug.Crypto.secure_compare(:crypto.hash(:sha256, token), expected),
          do: conn,
          else: unauthorized(conn)

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> reply({:error, %{code: "UNAUTHORIZED", message: "Local preview connection required"}})
    |> halt()
  end

  defp reply(conn, {:ok, result}), do: json(conn, 200, result)

  defp reply(conn, {:error, error}) do
    status =
      case error.code do
        "UNAUTHORIZED" -> 401
        "NOT_FOUND" -> 404
        "REVISION_CONFLICT" -> 409
        "VALIDATION_FAILED" -> 422
        _ -> 400
      end

    json(conn, status, %{error: error})
  end

  defp json(conn, status, value) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, Jason.encode!(value))
  end
end
