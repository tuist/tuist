defmodule TuistWeb.Plugs.GitHubWebhookPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.GitHubWebhookPlug

  defmodule TestHandler do
    @moduledoc false
    def handle(conn, payload) do
      send(self(), {:handled, conn, payload})
    end
  end

  defp generate_signature(payload, secret) do
    signature = :hmac |> :crypto.mac(:sha256, secret, payload) |> Base.encode16(case: :lower)
    "sha256=#{signature}"
  end

  defp webhook_request(method, path, payload, secret, _opts \\ []) do
    signature = generate_signature(payload, secret)

    method
    |> conn(path, payload)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-hub-signature-256", signature)
    |> Map.update!(:body_params, fn _ -> JSON.decode!(payload) end)
    |> assign(:raw_body, [payload])
  end

  describe "call/2" do
    test "processes webhook at configured path with valid signature" do
      # Given
      secret = "my-secret"
      payload = ~s({"action": "opened"})

      options = [
        at: "/webhook/github",
        secret: secret,
        handler: TestHandler
      ]

      conn = webhook_request(:post, "/webhook/github", payload, secret)

      # When
      result = GitHubWebhookPlug.call(conn, options)

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
        handler: TestHandler
      ]

      conn = webhook_request(:post, "/webhook/github", payload, invalid_secret)

      # When
      result = GitHubWebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
      assert result.resp_body == "Forbidden"
      assert result.halted == true

      refute_receive {:handled, _, _}
    end

    test "rejects tampered payload" do
      # Given
      secret = "test-secret"
      original_payload = ~s({"action": "opened"})
      tampered_payload = ~s({"action": "closed"})

      options = [at: "/webhook", secret: secret, handler: TestHandler]

      signature = generate_signature(original_payload, secret)

      conn =
        :post
        |> conn("/webhook", tampered_payload)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", signature)
        |> Map.update!(:body_params, fn _ -> JSON.decode!(tampered_payload) end)
        |> assign(:raw_body, [tampered_payload])

      # When
      result = GitHubWebhookPlug.call(conn, options)

      # Then
      assert result.status == 403
    end
  end
end
