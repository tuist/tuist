defmodule TuistWeb.Plugs.WebhookPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.WebhookPlug

  defmodule TestHandler do
    @moduledoc false
    def handle(conn, payload) do
      send(self(), {:handled, conn, payload})
      conn
    end
  end

  defp generate_signature(payload, secret, prefix \\ nil) do
    signature = :hmac |> :crypto.mac(:sha256, secret, payload) |> Base.encode16(case: :lower)

    if prefix do
      "#{prefix}#{signature}"
    else
      signature
    end
  end

  defp webhook_request(method, path, payload, secret, header_name, prefix \\ nil) do
    signature = generate_signature(payload, secret, prefix)

    method
    |> conn(path, payload)
    |> put_req_header("content-type", "application/json")
    |> put_req_header(header_name, signature)
    |> Map.update!(:body_params, fn _ -> Jason.decode!(payload) end)
    |> assign(:raw_body, [payload])
  end

  describe "call/2 with GitHub-style signature (with sha256= prefix)" do
    test "processes webhook at configured path with valid signature" do
      # Given
      secret = "my-secret"
      payload = ~s({"action": "opened"})

      options = [
        at: "/webhook/github",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-hub-signature-256",
        signature_prefix: "sha256="
      ]

      conn = webhook_request(:post, "/webhook/github", payload, secret, "x-hub-signature-256", "sha256=")

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      assert result.status == 200
      assert result.resp_body == "OK"
      assert result.halted == true

      assert_receive {:handled, _conn, %{"action" => "opened"}}
    end

    test "returns 403 for invalid signature" do
      # Given
      secret = "my-secret"
      invalid_secret = "wrong-secret"
      payload = ~s({"action": "opened"})

      options = [
        at: "/webhook/github",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-hub-signature-256",
        signature_prefix: "sha256="
      ]

      conn = webhook_request(:post, "/webhook/github", payload, invalid_secret, "x-hub-signature-256", "sha256=")

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
      assert result.resp_body == "Invalid signature"
      assert result.halted == true

      refute_receive {:handled, _, _}
    end

    test "rejects tampered payload" do
      # Given
      secret = "test-secret"
      original_payload = ~s({"action": "opened"})
      tampered_payload = ~s({"action": "closed"})

      options = [
        at: "/webhook",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-hub-signature-256",
        signature_prefix: "sha256="
      ]

      signature = generate_signature(original_payload, secret, "sha256=")

      conn =
        :post
        |> conn("/webhook", tampered_payload)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", signature)
        |> Map.update!(:body_params, fn _ -> Jason.decode!(tampered_payload) end)
        |> assign(:raw_body, [tampered_payload])

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
    end
  end

  describe "call/2 with cache-style signature (no prefix)" do
    test "processes webhook at configured path with valid signature" do
      # Given
      secret = "my-secret"
      payload = ~s({"events": [{"action": "upload", "size": 1024, "cas_id": "abc123"}]})

      options = [
        at: "/webhooks/cache",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-cache-signature"
      ]

      conn = webhook_request(:post, "/webhooks/cache", payload, secret, "x-cache-signature")

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      assert result.status == 200
      assert result.resp_body == "OK"
      assert result.halted == true

      assert_receive {:handled, _conn, %{"events" => [%{"action" => "upload", "size" => 1024, "cas_id" => "abc123"}]}}
    end

    test "returns 403 for invalid signature" do
      # Given
      secret = "my-secret"
      invalid_secret = "wrong-secret"
      payload = ~s({"events": []})

      options = [
        at: "/webhooks/cache",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-cache-signature"
      ]

      conn = webhook_request(:post, "/webhooks/cache", payload, invalid_secret, "x-cache-signature")

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
      assert result.resp_body == "Invalid signature"
      assert result.halted == true

      refute_receive {:handled, _, _}
    end

    test "returns 401 when signature header is missing" do
      # Given
      secret = "my-secret"
      payload = ~s({"events": []})

      options = [
        at: "/webhooks/cache",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-cache-signature"
      ]

      conn =
        :post
        |> conn("/webhooks/cache", payload)
        |> put_req_header("content-type", "application/json")
        |> Map.update!(:body_params, fn _ -> Jason.decode!(payload) end)
        |> assign(:raw_body, [payload])

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      assert result.status == 401
      assert result.resp_body == "Missing x-cache-signature header"
      assert result.halted == true

      refute_receive {:handled, _, _}
    end

    test "rejects tampered payload" do
      # Given
      secret = "test-secret"
      original_payload = ~s({"events": [{"action": "upload"}]})
      tampered_payload = ~s({"events": [{"action": "download"}]})

      options = [
        at: "/webhooks/cache",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-cache-signature"
      ]

      signature = generate_signature(original_payload, secret)

      conn =
        :post
        |> conn("/webhooks/cache", tampered_payload)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> Map.update!(:body_params, fn _ -> Jason.decode!(tampered_payload) end)
        |> assign(:raw_body, [tampered_payload])

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
      assert result.resp_body == "Invalid signature"
      assert result.halted == true

      refute_receive {:handled, _, _}
    end
  end

  describe "call/2 for non-matching paths" do
    test "passes through for non-matching paths" do
      # Given
      secret = "my-secret"
      payload = ~s({"action": "opened"})

      options = [
        at: "/webhook/github",
        secret: secret,
        handler: TestHandler,
        signature_header: "x-hub-signature-256"
      ]

      conn = webhook_request(:post, "/other/path", payload, secret, "x-hub-signature-256")

      # When
      result = WebhookPlug.call(conn, options)

      # Then
      refute result.halted
      refute result.status
      refute_receive {:handled, _, _}
    end
  end
end
