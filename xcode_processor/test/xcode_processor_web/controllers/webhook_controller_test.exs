defmodule XcodeProcessorWeb.WebhookControllerTest do
  use XcodeProcessorWeb.ConnCase
  use Mimic

  setup :verify_on_exit!

  @webhook_secret "test-webhook-secret"

  defp sign_payload(body) do
    :crypto.mac(:hmac, :sha256, @webhook_secret, body)
    |> Base.encode16(case: :lower)
  end

  describe "POST /webhooks/process-xcresult" do
    test "returns 200 with parsed data on successful processing", %{conn: conn} do
      parsed_data = %{"tests" => [%{"name" => "testExample", "status" => "passed"}]}

      expect(XcodeProcessor.XCResultProcessor, :process, fn "some/key.zip" ->
        {:ok, parsed_data}
      end)

      body =
        JSON.encode!(%{
          "test_run_id" => "run-123",
          "storage_key" => "some/key.zip",
          "project_id" => "project-456"
        })

      signature = sign_payload(body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-webhook-signature", signature)
        |> assign(:raw_body, [body])
        |> post("/webhooks/process-xcresult", body |> JSON.decode!())

      assert json_response(conn, 200) == Map.put(parsed_data, "project_id", "project-456")
    end

    test "returns 403 with invalid signature", %{conn: conn} do
      body =
        JSON.encode!(%{
          "test_run_id" => "run-123",
          "storage_key" => "some/key.zip",
          "project_id" => "project-456"
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-webhook-signature", "invalid-signature")
        |> assign(:raw_body, [body])
        |> post("/webhooks/process-xcresult", body |> JSON.decode!())

      assert json_response(conn, 403) == %{"error" => "Invalid signature"}
    end

    test "returns 401 when signature header is missing", %{conn: conn} do
      body =
        JSON.encode!(%{
          "test_run_id" => "run-123",
          "storage_key" => "some/key.zip",
          "project_id" => "project-456"
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:raw_body, [body])
        |> post("/webhooks/process-xcresult", body |> JSON.decode!())

      assert json_response(conn, 401) == %{"error" => "Missing x-webhook-signature header"}
    end

    test "returns 500 when webhook secret is not configured", %{conn: conn} do
      stub(XcodeProcessor.Environment, :webhook_secret, fn -> nil end)

      body =
        JSON.encode!(%{
          "test_run_id" => "run-123",
          "storage_key" => "some/key.zip",
          "project_id" => "project-456"
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:raw_body, [body])
        |> post("/webhooks/process-xcresult", body |> JSON.decode!())

      assert json_response(conn, 500) == %{"error" => "Webhook secret not configured"}
    end
  end
end
