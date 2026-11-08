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
      |> put_req_header("sec-websocket-protocol", "phoenix, base64url.bearer.phx.secret")
      |> put_req_header("x-tuist-actor-id", "jane.doe")
      |> put_req_header("x-tuist-runner-grant", "signed.runner.grant")
      |> put_req_header("x-csrf-token", "session-csrf-token")
      |> put_req_header("accept", "application/json")

    assert TuistWeb.Endpoint.scrub_sentry_headers(conn) == %{"accept" => "application/json"}

    request =
      Sentry.PlugContext.build_request_interface_data(conn,
        header_scrubber: {TuistWeb.Endpoint, :scrub_sentry_headers}
      )

    assert request.headers == %{"accept" => "application/json"}
  end

  test "keeps private jam request bodies out of Sentry" do
    for collection <- ["jams", "threads"] do
      conn = %{
        Plug.Test.conn(:post, "/api/accounts/account/#{collection}/jam/messages")
        | params: %{"content" => "Private conversation", "request_id" => "private-approval"}
      }

      request =
        Sentry.PlugContext.build_request_interface_data(conn, body_scrubber: {TuistWeb.Endpoint, :scrub_sentry_body})

      assert request.data == %{}
    end
  end

  test "keeps second-factor codes out of Sentry request bodies" do
    conn = %{Plug.Test.conn(:post, "/users/mfa") | params: %{"mfa_code" => "RECOVERYCODE", "recovery" => "true"}}

    request =
      Sentry.PlugContext.build_request_interface_data(conn, body_scrubber: {TuistWeb.Endpoint, :scrub_sentry_body})

    assert request.data == %{"recovery" => "true"}
  end

  test "keeps subscription tokens and MCP tool arguments out of Sentry request bodies" do
    params = %{
      "token" => "sk-ant-oat01-secret",
      "jsonrpc" => "2.0",
      "params" => %{"name" => "connect_claude_subscription", "arguments" => %{"token" => "sk-ant-oat01-secret"}},
      "batch" => [%{"params" => %{"arguments" => %{"token" => "sk-ant-oat01-secret"}}}]
    }

    conn = %{Plug.Test.conn(:post, "/mcp") | params: params}

    request =
      Sentry.PlugContext.build_request_interface_data(conn, body_scrubber: {TuistWeb.Endpoint, :scrub_sentry_body})

    assert request.data == %{
             "jsonrpc" => "2.0",
             "params" => %{"name" => "connect_claude_subscription"},
             "batch" => [%{"params" => %{}}]
           }
  end
end
