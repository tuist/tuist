defmodule XcodeProcessorWeb.Plugs.WebhookAuthPlugTest do
  use ExUnit.Case

  alias XcodeProcessorWeb.Plugs.WebhookAuthPlug

  @webhook_secret "test-webhook-secret"

  defp build_conn(body, headers \\ []) do
    conn =
      Plug.Test.conn(:post, "/webhooks/process-xcresult", body)
      |> Plug.Conn.assign(:raw_body, [body])

    Enum.reduce(headers, conn, fn {key, value}, acc ->
      Plug.Conn.put_req_header(acc, key, value)
    end)
  end

  defp sign_payload(body) do
    :crypto.mac(:hmac, :sha256, @webhook_secret, body)
    |> Base.encode16(case: :lower)
  end

  describe "call/2" do
    test "passes through with valid signature" do
      body = ~s({"test": "data"})
      signature = sign_payload(body)
      conn = build_conn(body, [{"x-webhook-signature", signature}])

      result = WebhookAuthPlug.call(conn, [])

      refute result.halted
    end

    test "rejects with 403 when signature is invalid" do
      body = ~s({"test": "data"})
      conn = build_conn(body, [{"x-webhook-signature", "bad-signature"}])

      result = WebhookAuthPlug.call(conn, [])

      assert result.halted
      assert result.status == 403
      assert JSON.decode!(result.resp_body) == %{"error" => "Invalid signature"}
    end

    test "rejects with 401 when signature header is missing" do
      body = ~s({"test": "data"})
      conn = build_conn(body)

      result = WebhookAuthPlug.call(conn, [])

      assert result.halted
      assert result.status == 401
      assert JSON.decode!(result.resp_body) == %{"error" => "Missing x-webhook-signature header"}
    end

    test "rejects with 500 when webhook secret is nil" do
      original_secret = Application.get_env(:xcode_processor, :webhook_secret)
      Application.put_env(:xcode_processor, :webhook_secret, nil)

      on_exit(fn ->
        Application.put_env(:xcode_processor, :webhook_secret, original_secret)
      end)

      body = ~s({"test": "data"})
      conn = build_conn(body, [{"x-webhook-signature", "some-sig"}])

      result = WebhookAuthPlug.call(conn, [])

      assert result.halted
      assert result.status == 500
      assert JSON.decode!(result.resp_body) == %{"error" => "Webhook secret not configured"}
    end

    test "rejects with 500 when webhook secret is empty string" do
      original_secret = Application.get_env(:xcode_processor, :webhook_secret)
      Application.put_env(:xcode_processor, :webhook_secret, "")

      on_exit(fn ->
        Application.put_env(:xcode_processor, :webhook_secret, original_secret)
      end)

      body = ~s({"test": "data"})
      conn = build_conn(body, [{"x-webhook-signature", "some-sig"}])

      result = WebhookAuthPlug.call(conn, [])

      assert result.halted
      assert result.status == 500
      assert JSON.decode!(result.resp_body) == %{"error" => "Webhook secret not configured"}
    end
  end
end
