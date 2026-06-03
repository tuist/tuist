defmodule TuistWeb.Plugs.SlackWebhookPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.SlackWebhookPlug

  @secret "test-signing-secret"
  @path "/webhooks/tailscale-jit/slash"

  defmodule FakeHandler do
    @moduledoc false
    def slash(conn, params) do
      Plug.Conn.send_resp(conn, 200, Jason.encode!(%{ok: true, params: params}))
    end
  end

  describe "signature verification" do
    test "accepts a correctly-signed request" do
      body = "text=elevate+staging+fix+the+thing"
      ts = Integer.to_string(System.system_time(:second))
      conn = signed_conn(body, ts)

      conn = SlackWebhookPlug.call(conn, opts())

      assert conn.status == 200
      assert conn.resp_body =~ "\"ok\":true"
    end

    test "rejects a request with a mismatched signature" do
      body = "text=elevate+staging+fix+the+thing"
      ts = Integer.to_string(System.system_time(:second))
      conn = bad_signed_conn(body, ts)

      conn = SlackWebhookPlug.call(conn, opts())

      assert conn.status == 403
    end

    test "rejects a request whose timestamp is older than 5 minutes" do
      body = "text=elevate+staging+fix+the+thing"
      old = Integer.to_string(System.system_time(:second) - 10 * 60)
      conn = signed_conn(body, old)

      conn = SlackWebhookPlug.call(conn, opts())

      assert conn.status == 403
    end

    test "rejects when X-Slack-Signature header is missing" do
      body = "text=elevate+staging+fix+the+thing"
      ts = Integer.to_string(System.system_time(:second))

      conn =
        :post
        |> conn(@path, body)
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("x-slack-request-timestamp", ts)

      conn = SlackWebhookPlug.call(conn, opts())

      assert conn.status == 401
    end
  end

  defp signed_conn(body, ts) do
    payload = "v0:#{ts}:#{body}"
    sig = "v0=" <> (:hmac |> :crypto.mac(:sha256, @secret, payload) |> Base.encode16(case: :lower))

    :post
    |> conn(@path, body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-slack-request-timestamp", ts)
    |> put_req_header("x-slack-signature", sig)
  end

  defp bad_signed_conn(body, ts) do
    sig = "v0=" <> String.duplicate("0", 64)

    :post
    |> conn(@path, body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-slack-request-timestamp", ts)
    |> put_req_header("x-slack-signature", sig)
  end

  defp opts do
    SlackWebhookPlug.init(
      at: @path,
      handler: FakeHandler,
      action: :slash,
      secret: @secret
    )
  end
end
