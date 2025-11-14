defmodule TuistWeb.Plugs.CacheWebhookPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.CacheWebhookPlug

  defmodule TestHandler do
    @moduledoc false
    def handle(conn, payload) do
      send(self(), {:handled, conn, payload})

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(202, Jason.encode!(%{}))
      |> halt()
    end
  end

  defp generate_signature(payload, secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp webhook_request(method, path, payload, secret, _opts \\ []) do
    signature = generate_signature(payload, secret)

    method
    |> conn(path, payload)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cache-signature", signature)
    |> Map.update!(:body_params, fn _ -> Jason.decode!(payload) end)
    |> assign(:raw_body, [payload])
  end

  describe "call/2" do
    test "processes webhook at configured path with valid signature" do
      # Given
      secret = "my-secret"
      payload = ~s({"events": [{"action": "upload", "size": 1024, "cas_id": "abc123"}]})

      options = [
        at: "/webhooks/cache",
        secret: secret,
        handler: TestHandler
      ]

      conn = webhook_request(:post, "/webhooks/cache", payload, secret)

      # When
      result = CacheWebhookPlug.call(conn, options)

      # Then
      assert result.status == 202
      assert result.halted == true

      assert_receive {:handled, _conn,
                      %{"events" => [%{"action" => "upload", "size" => 1024, "cas_id" => "abc123"}]}}
    end

    test "returns 403 for invalid signature" do
      # Given
      secret = "my-secret"
      invalid_secret = "wrong-secret"
      payload = ~s({"events": []})

      options = [
        at: "/webhooks/cache",
        secret: secret,
        handler: TestHandler
      ]

      conn = webhook_request(:post, "/webhooks/cache", payload, invalid_secret)

      # When
      result = CacheWebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
      assert result.resp_body == "Invalid signature"
      assert result.halted == true

      refute_receive {:handled, _, _}
    end

    test "returns 401 when x-cache-signature header is missing" do
      # Given
      secret = "my-secret"
      payload = ~s({"events": []})

      options = [
        at: "/webhooks/cache",
        secret: secret,
        handler: TestHandler
      ]

      conn =
        :post
        |> conn("/webhooks/cache", payload)
        |> put_req_header("content-type", "application/json")
        |> Map.update!(:body_params, fn _ -> Jason.decode!(payload) end)
        |> assign(:raw_body, [payload])

      # When
      result = CacheWebhookPlug.call(conn, options)

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

      options = [at: "/webhooks/cache", secret: secret, handler: TestHandler]

      signature = generate_signature(original_payload, secret)

      conn =
        :post
        |> conn("/webhooks/cache", tampered_payload)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> Map.update!(:body_params, fn _ -> Jason.decode!(tampered_payload) end)
        |> assign(:raw_body, [tampered_payload])

      # When
      result = CacheWebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
      assert result.resp_body == "Invalid signature"
      assert result.halted == true

      refute_receive {:handled, _, _}
    end
  end
end
