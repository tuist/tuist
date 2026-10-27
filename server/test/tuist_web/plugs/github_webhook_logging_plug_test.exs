defmodule TuistWeb.Plugs.GitHubWebhookLoggingPlugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.GitHubWebhookLoggingPlug

  test "logs request metadata for github webhook traffic" do
    # Given
    conn =
      :post
      |> conn("/webhooks/github", "")
      |> put_req_header("user-agent", "GitHub-Hookshot/abc123")
      |> put_req_header("x-github-event", "installation")
      |> put_req_header("x-github-delivery", "delivery-123")
      |> put_req_header("x-hub-signature-256", "sha256=secret")
      |> put_req_header("content-length", "123")
      |> put_req_header("x-forwarded-for", "203.0.113.10")

    # When
    conn = GitHubWebhookLoggingPlug.call(conn, %{})
    [before_send_hook] = conn.private.before_send

    log =
      capture_log(fn ->
        before_send_hook.(%{conn | status: 408})
      end)

    # Then
    assert log =~ "GitHub webhook request"
    assert log =~ "request_path: \"/webhooks/github\""
    assert log =~ "status: 408"
    assert log =~ "remote_ip: \"203.0.113.10\""
    assert log =~ "user_agent: \"GitHub-Hookshot/abc123\""
    assert log =~ "github_event: \"installation\""
    assert log =~ "github_delivery: \"delivery-123\""
    assert log =~ "content_length: \"123\""
    assert log =~ "has_signature: true"
  end

  test "does not register a logger for non-github webhook paths" do
    # Given
    conn = conn(:post, "/webhooks/cache", "")

    # When
    conn = GitHubWebhookLoggingPlug.call(conn, %{})

    # Then
    assert conn.private[:before_send] in [nil, []]
  end
end
