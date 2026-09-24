defmodule TuistWeb.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  test "keeps credential headers out of Sentry events" do
    conn =
      :post
      |> Plug.Test.conn("/mcp")
      |> put_req_header("x-tuist-atlas-identity", "sa-token")
      |> put_req_header("authorization", "Bearer token")
      |> put_req_header("accept", "application/json")

    assert TuistWeb.Endpoint.scrub_sentry_headers(conn) == %{"accept" => "application/json"}
  end
end
