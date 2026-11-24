defmodule TuistWeb.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  test "conversation sockets and routes are retired without removing generic sockets or capabilities" do
    sockets = Enum.map(TuistWeb.Endpoint.__sockets__(), &elem(&1, 0))
    assert "/live" in sockets
    assert "/socket" in sockets
    refute "/threads/socket" in sockets
    refute "/jams/socket" in sockets

    paths = Enum.map(TuistWeb.Router.__routes__(), & &1.path)

    for prefix <- [
          "/api/accounts/:account_handle/threads",
          "/api/accounts/:account_handle/jams",
          "/api/accounts/:account_handle/halls",
          "/api/me/thread-runners",
          "/api/thread-runner"
        ] do
      refute Enum.any?(paths, &String.starts_with?(&1, prefix))
    end

    assert "/api/accounts/:account_handle/luft-context" in paths
    assert "/api/accounts/:account_handle/workspace-capabilities" in paths
  end

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

  test "keeps second-factor codes out of Sentry request bodies" do
    conn = %{Plug.Test.conn(:post, "/users/mfa") | params: %{"mfa_code" => "RECOVERYCODE", "recovery" => "true"}}

    request =
      Sentry.PlugContext.build_request_interface_data(conn, body_scrubber: {TuistWeb.Endpoint, :scrub_sentry_body})

    assert request.data == %{"recovery" => "true"}
  end

  test "keeps provider keys, subscription tokens and MCP tool arguments out of logs and Sentry request bodies" do
    params = %{
      "token" => "sk-ant-oat01-secret",
      "route" => %{"provider" => "openai", "api_key" => "provider-secret"},
      "jsonrpc" => "2.0",
      "params" => %{"name" => "connect_claude_subscription", "arguments" => %{"token" => "sk-ant-oat01-secret"}},
      "batch" => [%{"params" => %{"arguments" => %{"token" => "sk-ant-oat01-secret"}}}]
    }

    assert Phoenix.Logger.filter_values(params)["route"] == %{"provider" => "openai", "api_key" => "[FILTERED]"}

    conn = %{Plug.Test.conn(:post, "/mcp") | params: params}

    request =
      Sentry.PlugContext.build_request_interface_data(conn, body_scrubber: {TuistWeb.Endpoint, :scrub_sentry_body})

    assert request.data == %{
             "jsonrpc" => "2.0",
             "route" => %{"provider" => "openai"},
             "params" => %{"name" => "connect_claude_subscription"},
             "batch" => [%{"params" => %{}}]
           }
  end
end
