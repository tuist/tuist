defmodule TuistWeb.Plugs.SlackWebhookPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.SlackWebhookPlug

  defmodule TestHandler do
    @moduledoc false
    def handle(conn, payload) do
      send(self(), {:handled, conn, payload})
      conn
    end
  end

  defp slack_signature(secret, timestamp, body) do
    basestring = "v0:#{timestamp}:#{body}"

    sig =
      :hmac
      |> :crypto.mac(:sha256, secret, basestring)
      |> Base.encode16(case: :lower)

    "v0=#{sig}"
  end

  defp current_timestamp, do: :second |> System.system_time() |> to_string()

  defp slack_request(path, payload, secret, timestamp \\ nil) do
    ts = timestamp || current_timestamp()
    signature = slack_signature(secret, ts, payload)

    :post
    |> conn(path, payload)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-slack-request-timestamp", ts)
    |> put_req_header("x-slack-signature", signature)
    |> Map.update!(:body_params, fn _ -> Jason.decode!(payload) end)
    |> assign(:raw_body, [payload])
  end

  describe "call/2 with valid Slack signature" do
    test "processes webhook at configured path" do
      secret = "slack-signing-secret"
      payload = ~s({"event":{"type":"link_shared"}})

      options = [at: "/webhooks/slack", secret: secret, handler: TestHandler]
      conn = slack_request("/webhooks/slack", payload, secret)

      result = SlackWebhookPlug.call(conn, SlackWebhookPlug.init(options))

      assert result.status == 200
      assert result.resp_body == "OK"
      assert result.halted == true
      assert_receive {:handled, _conn, %{"event" => %{"type" => "link_shared"}}}
    end
  end

  describe "call/2 with invalid signature" do
    test "returns 403" do
      secret = "slack-signing-secret"
      wrong_secret = "wrong-secret"
      payload = ~s({"event":{"type":"link_shared"}})

      options = [at: "/webhooks/slack", secret: secret, handler: TestHandler]
      conn = slack_request("/webhooks/slack", payload, wrong_secret)

      result = SlackWebhookPlug.call(conn, SlackWebhookPlug.init(options))

      assert result.status == 403
      assert result.resp_body == "Invalid signature"
      assert result.halted == true
      refute_receive {:handled, _, _}
    end
  end

  describe "call/2 with missing headers" do
    test "returns 401 when signature headers are missing" do
      secret = "slack-signing-secret"
      payload = ~s({"event":{"type":"link_shared"}})

      options = [at: "/webhooks/slack", secret: secret, handler: TestHandler]

      conn =
        :post
        |> conn("/webhooks/slack", payload)
        |> put_req_header("content-type", "application/json")
        |> Map.update!(:body_params, fn _ -> Jason.decode!(payload) end)
        |> assign(:raw_body, [payload])

      result = SlackWebhookPlug.call(conn, SlackWebhookPlug.init(options))

      assert result.status == 401
      assert result.resp_body == "Missing Slack signature headers"
      assert result.halted == true
      refute_receive {:handled, _, _}
    end
  end

  describe "call/2 with expired timestamp" do
    test "returns 403 for stale timestamp" do
      secret = "slack-signing-secret"
      payload = ~s({"event":{"type":"link_shared"}})
      stale_timestamp = to_string(System.system_time(:second) - 600)

      options = [at: "/webhooks/slack", secret: secret, handler: TestHandler]
      conn = slack_request("/webhooks/slack", payload, secret, stale_timestamp)

      result = SlackWebhookPlug.call(conn, SlackWebhookPlug.init(options))

      assert result.status == 403
      assert result.resp_body == "Stale timestamp"
      assert result.halted == true
      refute_receive {:handled, _, _}
    end
  end

  describe "call/2 with url_verification" do
    test "echoes back the challenge token after signature verification" do
      secret = "slack-signing-secret"
      challenge = "test-challenge-token-12345"
      payload = Jason.encode!(%{type: "url_verification", challenge: challenge})

      options = [at: "/webhooks/slack", secret: secret, handler: TestHandler]
      conn = slack_request("/webhooks/slack", payload, secret)

      result = SlackWebhookPlug.call(conn, SlackWebhookPlug.init(options))

      assert result.status == 200
      assert result.resp_body == challenge
      assert result.halted == true
      refute_receive {:handled, _, _}
    end

    test "rejects unsigned challenge requests" do
      secret = "slack-signing-secret"
      challenge = "test-challenge-token-12345"
      payload = Jason.encode!(%{type: "url_verification", challenge: challenge})
      options = [at: "/webhooks/slack", secret: secret, handler: TestHandler]

      conn =
        :post
        |> conn("/webhooks/slack", payload)
        |> put_req_header("content-type", "application/json")
        |> Map.update!(:body_params, fn _ -> Jason.decode!(payload) end)
        |> assign(:raw_body, [payload])

      result = SlackWebhookPlug.call(conn, SlackWebhookPlug.init(options))

      assert result.status == 401
      assert result.resp_body == "Missing Slack signature headers"
      assert result.halted == true
      refute_receive {:handled, _, _}
    end
  end

  describe "call/2 for non-matching paths" do
    test "passes through" do
      secret = "slack-signing-secret"
      payload = ~s({"event":{"type":"link_shared"}})

      options = [at: "/webhooks/slack", secret: secret, handler: TestHandler]
      conn = slack_request("/other/path", payload, secret)

      result = SlackWebhookPlug.call(conn, SlackWebhookPlug.init(options))

      refute result.halted
      refute result.status
      refute_receive {:handled, _, _}
    end
  end
end
