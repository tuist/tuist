defmodule TuistWeb.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  test "keeps credential headers and actor claims out of Sentry events" do
    conn =
      :post
      |> Plug.Test.conn("/mcp")
      |> put_req_header("x-tuist-atlas-identity", "sa-token")
      |> put_req_header("x-tuist-operator-grant", "grant")
      |> put_req_header("authorization", "Bearer token")
      |> put_req_header("x-tuist-actor-id", "jane.doe")
      |> put_req_header("accept", "application/json")

    assert TuistWeb.Endpoint.scrub_sentry_headers(conn) == %{"accept" => "application/json"}

    request =
      Sentry.PlugContext.build_request_interface_data(conn,
        header_scrubber: {TuistWeb.Endpoint, :scrub_sentry_headers}
      )

    assert request.headers == %{"accept" => "application/json"}
  end
end
