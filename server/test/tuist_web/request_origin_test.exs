defmodule TuistWeb.RequestOriginTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.RequestOrigin

  test "uses conn origin when forwarded headers are not present" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :https)
      |> Map.put(:host, "tuist.dev")
      |> Map.put(:port, 443)

    assert RequestOrigin.from_conn(conn) == "https://tuist.dev"
  end

  test "uses forwarded origin with host and port" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :http)
      |> Map.put(:host, "internal")
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "mcp.tuist.dev")
      |> put_req_header("x-forwarded-port", "8443")

    assert RequestOrigin.from_conn(conn) == "https://mcp.tuist.dev:8443"
  end

  test "does not append forwarded port when host already includes one" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :http)
      |> Map.put(:host, "internal")
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "mcp.tuist.dev:9443")
      |> put_req_header("x-forwarded-port", "8443")

    assert RequestOrigin.from_conn(conn) == "https://mcp.tuist.dev:9443"
  end

  test "uses first value when forwarded headers contain a list" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :http)
      |> Map.put(:host, "internal")
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https, http")
      |> put_req_header("x-forwarded-host", "tuist.dev, internal")
      |> put_req_header("x-forwarded-port", "443, 4000")

    assert RequestOrigin.from_conn(conn) == "https://tuist.dev"
  end
end
