defmodule TuistWeb.Plugs.RequireCacheEndpointPlug do
  @moduledoc """
  Validates that the `x-cache-endpoint` header is present and non-empty.

  On success, assigns `:cache_endpoint` to `conn.assigns`.
  On failure, halts with 400 Bad Request.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, "x-cache-endpoint") do
      [cache_endpoint] when cache_endpoint != "" ->
        assign(conn, :cache_endpoint, cache_endpoint)

      _ ->
        conn
        |> put_status(:bad_request)
        |> Phoenix.Controller.json(%{error: "Missing x-cache-endpoint header"})
        |> halt()
    end
  end
end
