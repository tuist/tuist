defmodule TuistWeb.Webhooks.RegistryControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Registry.DownloadEvent

  @cache_api_key "test-registry-api-key"

  setup %{conn: conn} do
    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)

    %{conn: conn}
  end

  defp sign_request(body) do
    json_body = Jason.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    {json_body, signature}
  end

  describe "POST /webhooks/registry" do
    test "creates download events with valid payload and verifies in ClickHouse", %{conn: conn} do
      unique_scope = "valid-test-#{System.unique_integer([:positive])}"

      params = %{
        "events" => [
          %{"scope" => unique_scope, "name" => "swift-nio", "version" => "2.0.0"}
        ]
      }

      {body, signature} = sign_request(params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> post(~p"/webhooks/registry", body)

      assert json_response(conn, 202) == %{}

      events =
        ClickHouseRepo.all(from(e in DownloadEvent, where: e.scope == ^unique_scope))

      assert length(events) == 1
      [event] = events
      assert event.scope == unique_scope
      assert event.name == "swift-nio"
      assert event.version == "2.0.0"
    end

    test "returns 400 for invalid payload without events key", %{conn: conn} do
      params = %{"invalid" => "data"}

      {body, signature} = sign_request(params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> post(~p"/webhooks/registry", body)

      assert json_response(conn, 400) == %{"error" => "Invalid payload"}
    end

    test "handles batch of multiple events and all are inserted", %{conn: conn} do
      unique_scope = "batch-test-#{System.unique_integer([:positive])}"

      params = %{
        "events" => [
          %{"scope" => unique_scope, "name" => "swift-nio", "version" => "2.0.0"},
          %{"scope" => unique_scope, "name" => "swift-log", "version" => "1.5.0"},
          %{"scope" => unique_scope, "name" => "xcodeproj", "version" => "3.0.0"}
        ]
      }

      {body, signature} = sign_request(params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> post(~p"/webhooks/registry", body)

      assert json_response(conn, 202) == %{}

      events =
        ClickHouseRepo.all(
          from(e in DownloadEvent,
            where: e.scope == ^unique_scope,
            order_by: e.name
          )
        )

      assert length(events) == 3
      names = Enum.map(events, & &1.name)
      assert "swift-log" in names
      assert "swift-nio" in names
      assert "xcodeproj" in names
    end

    test "rejects requests with invalid signature", %{conn: conn} do
      params = %{
        "events" => [
          %{"scope" => "apple", "name" => "swift-nio", "version" => "2.0.0"}
        ]
      }

      json_body = Jason.encode!(params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", "invalid_signature")
        |> post(~p"/webhooks/registry", json_body)

      assert conn.status == 403
      assert conn.resp_body == "Invalid signature"
    end
  end
end
