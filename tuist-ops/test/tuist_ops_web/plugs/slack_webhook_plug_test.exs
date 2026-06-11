defmodule TuistOpsWeb.Plugs.SlackWebhookPlugTest do
  @moduledoc """
  Slack's signing scheme: HMAC-SHA256 over
  `v0:<unix_timestamp>:<raw_body>` with the signing secret, hex-
  encoded, sent as `X-Slack-Signature: v0=<hex>`. The plug also
  enforces a ±5-minute timestamp window to bound replay.

  Security-critical: a bypass here means anything can POST to
  /webhooks/slack/* and impersonate Slack-signed events (trigger
  fake /elevate calls, click fake Approve actions).
  """

  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias TuistOps.Environment
  alias TuistOpsWeb.Plugs.SlackWebhookPlug

  setup :verify_on_exit!

  @secret "test-signing-secret"

  defp sign(secret, timestamp, body) do
    payload = "v0:#{timestamp}:#{body}"
    hex = :hmac |> :crypto.mac(:sha256, secret, payload) |> Base.encode16(case: :lower)
    "v0=#{hex}"
  end

  defp build_signed_conn(body, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, System.system_time(:second))
    signature = Keyword.get(opts, :signature) || sign(@secret, timestamp, body)

    :post
    |> conn("/webhooks/slack/slash", body)
    |> put_req_header("x-slack-signature", signature)
    |> put_req_header("x-slack-request-timestamp", to_string(timestamp))
    |> assign(:raw_body, body)
  end

  describe "valid signature" do
    setup do
      stub(Environment, :slack_signing_secret, fn -> @secret end)
      :ok
    end

    test "passes through unmodified" do
      conn = "text=hello" |> build_signed_conn() |> SlackWebhookPlug.call([])
      refute conn.halted
      assert conn.status == nil
    end

    test "accepts empty body" do
      conn = "" |> build_signed_conn() |> SlackWebhookPlug.call([])
      refute conn.halted
    end

    test "accepts raw_body as iolist" do
      body = "text=approve"
      timestamp = System.system_time(:second)

      conn =
        :post
        |> conn("/webhooks/slack/interactive", body)
        |> put_req_header("x-slack-signature", sign(@secret, timestamp, body))
        |> put_req_header("x-slack-request-timestamp", to_string(timestamp))
        # Phoenix Plug.Parsers can hand body to plugs as iodata.
        |> assign(:raw_body, [body])
        |> SlackWebhookPlug.call([])

      refute conn.halted
    end
  end

  describe "signature rejection (security-critical)" do
    setup do
      stub(Environment, :slack_signing_secret, fn -> @secret end)
      :ok
    end

    test "tampered body → 403" do
      timestamp = System.system_time(:second)
      legit_sig = sign(@secret, timestamp, "text=approve")

      conn =
        :post
        |> conn("/webhooks/slack/slash", "text=DELETE_EVERYTHING")
        |> put_req_header("x-slack-signature", legit_sig)
        |> put_req_header("x-slack-request-timestamp", to_string(timestamp))
        |> assign(:raw_body, "text=DELETE_EVERYTHING")
        |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
      assert conn.resp_body =~ "Invalid Slack signature"
    end

    test "wrong signing secret (key rotation desync) → 403" do
      timestamp = System.system_time(:second)
      bad_sig = sign("WRONG_SECRET", timestamp, "text=x")

      conn =
        "text=x"
        |> build_signed_conn(timestamp: timestamp, signature: bad_sig)
        |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "missing X-Slack-Signature header → 403" do
      timestamp = System.system_time(:second)

      conn =
        :post
        |> conn("/webhooks/slack/slash", "x")
        |> put_req_header("x-slack-request-timestamp", to_string(timestamp))
        |> assign(:raw_body, "x")
        |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "missing X-Slack-Request-Timestamp header → 403" do
      conn =
        :post
        |> conn("/webhooks/slack/slash", "x")
        |> put_req_header("x-slack-signature", "v0=abc")
        |> assign(:raw_body, "x")
        |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "malformed timestamp (non-integer) → 403" do
      conn =
        "text=x"
        |> build_signed_conn(timestamp: "not-a-number")
        |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "stale timestamp (replay window expired) → 403" do
      stale_ts = System.system_time(:second) - 600

      conn =
        "text=x"
        |> build_signed_conn(timestamp: stale_ts)
        |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "future-skewed timestamp beyond tolerance → 403" do
      future_ts = System.system_time(:second) + 600

      conn =
        "text=x"
        |> build_signed_conn(timestamp: future_ts)
        |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "timestamp at the edge of tolerance (~5 min) → still passes" do
      edge_ts = System.system_time(:second) - 295

      conn =
        "text=x"
        |> build_signed_conn(timestamp: edge_ts)
        |> SlackWebhookPlug.call([])

      refute conn.halted
    end
  end

  describe "secret resolution" do
    test "nil signing secret → 403 (don't accidentally accept all requests)" do
      stub(Environment, :slack_signing_secret, fn -> nil end)

      conn = "x" |> build_signed_conn() |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "empty string signing secret → 403" do
      stub(Environment, :slack_signing_secret, fn -> "" end)

      conn = "x" |> build_signed_conn() |> SlackWebhookPlug.call([])

      assert conn.halted
      assert conn.status == 403
    end
  end
end
