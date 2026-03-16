defmodule FlakyFixRunnerWeb.WebhookControllerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint FlakyFixRunnerWeb.Endpoint

  defp sign_body(body) do
    :crypto.mac(:hmac, :sha256, "test-webhook-secret", body)
    |> Base.encode16(case: :lower)
  end

  defp post_webhook(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/webhooks/fix-flaky-test", body)
  end

  describe "POST /webhooks/fix-flaky-test" do
    test "returns 401 when x-webhook-signature header is missing" do
      body = Jason.encode!(%{"job_id" => 1})

      conn =
        build_conn()
        |> post_webhook(body)

      assert conn.status == 401
      assert json_response(conn, 401) == %{"error" => "Missing x-webhook-signature header"}
    end

    test "returns 403 when x-webhook-signature is invalid" do
      body = Jason.encode!(%{"job_id" => 1})

      conn =
        build_conn()
        |> put_req_header("x-webhook-signature", "invalid-signature")
        |> post_webhook(body)

      assert conn.status == 403
      assert json_response(conn, 403) == %{"error" => "Invalid signature"}
    end

    test "returns 400 for a signed but invalid payload" do
      body = Jason.encode!(%{"job_id" => 1})

      conn =
        build_conn()
        |> put_req_header("x-webhook-signature", sign_body(body))
        |> post_webhook(body)

      assert conn.status == 400
      assert json_response(conn, 400) == %{"error" => "Invalid payload"}
    end
  end
end
