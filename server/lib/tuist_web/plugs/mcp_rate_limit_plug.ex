defmodule TuistWeb.Plugs.MCPRateLimitPlug do
  @moduledoc false

  use TuistWeb, :controller

  alias TuistWeb.RateLimit

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    case RateLimit.MCP.hit(conn) do
      {:allow, _} ->
        conn

      {:deny, _} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{
          jsonrpc: "2.0",
          id: Map.get(conn.params, "id"),
          error: %{code: -32_603, message: "Rate limit exceeded. Please try again later."}
        })
        |> halt()
    end
  end
end
