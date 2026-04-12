defmodule ProcessorWeb.WebhookControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint ProcessorWeb.Endpoint

  @valid_payload %{
    "build_id" => "build-123",
    "storage_key" => "some/storage/key.xcactivitylog",
    "account_id" => "account-456",
    "project_id" => "project-789",
    "xcode_cache_upload_enabled" => true
  }

  defp sign_body(body) do
    :crypto.mac(:hmac, :sha256, "test-webhook-secret", body)
    |> Base.encode16(case: :lower)
  end

  defp post_webhook(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/webhooks/process-build", body)
  end

  describe "POST /webhooks/process-build" do
    test "returns 401 when x-webhook-signature header is missing" do
      body = JSON.encode!(@valid_payload)

      conn =
        build_conn()
        |> post_webhook(body)

      assert conn.status == 401
      assert json_response(conn, 401) == %{"error" => "Missing x-webhook-signature header"}
    end

    test "returns 403 when x-webhook-signature is invalid" do
      body = JSON.encode!(@valid_payload)

      conn =
        build_conn()
        |> put_req_header("x-webhook-signature", "invalid-signature")
        |> post_webhook(body)

      assert conn.status == 403
      assert json_response(conn, 403) == %{"error" => "Invalid signature"}
    end

    test "returns 200 with parsed data when signature is valid and processing succeeds" do
      expect(Processor.BuildProcessor, :process, fn _storage_key, true ->
        {:ok, %{"duration" => 1200, "targets" => []}}
      end)

      body = JSON.encode!(@valid_payload)
      signature = sign_body(body)

      conn =
        build_conn()
        |> put_req_header("x-webhook-signature", signature)
        |> post_webhook(body)

      assert conn.status == 200

      response = json_response(conn, 200)
      assert response["duration"] == 1200
      assert response["targets"] == []
      assert response["project_id"] == "project-789"
    end

    test "returns 422 when processing fails" do
      expect(Processor.BuildProcessor, :process, fn _storage_key, true ->
        {:error, "download failed"}
      end)

      body = JSON.encode!(@valid_payload)
      signature = sign_body(body)

      conn =
        build_conn()
        |> put_req_header("x-webhook-signature", signature)
        |> post_webhook(body)

      assert conn.status == 422
      assert json_response(conn, 422)["error"] == "processing_failed"
    end
  end
end
