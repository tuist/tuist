defmodule TuistWeb.Webhooks.GradleCacheControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle.CacheEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @cache_api_key "test-cache-api-key"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)

    %{conn: conn, user: user, project: project}
  end

  defp sign_request(body) do
    json_body = Jason.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    {json_body, signature}
  end

  describe "POST /webhooks/gradle-cache" do
    test "creates multiple Gradle cache events with valid signature", %{conn: conn, project: project} do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 1024,
            "cache_key" => "gradle-key-abc123"
          },
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "download",
            "size" => 2048,
            "cache_key" => "gradle-key-def456"
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> post(~p"/webhooks/gradle-cache", body)

      assert json_response(conn, 202) == %{}

      events =
        ClickHouseRepo.all(from e in CacheEvent, where: e.project_id == ^project.id, order_by: e.size)

      assert length(events) == 2

      [event1, event2] = events

      assert event1.action == "upload"
      assert event1.size == 1024
      assert event1.cache_key == "gradle-key-abc123"
      assert event1.project_id == project.id

      assert event2.action == "download"
      assert event2.size == 2048
      assert event2.cache_key == "gradle-key-def456"
      assert event2.project_id == project.id
    end

    test "rejects requests with invalid signature", %{conn: conn, project: project} do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 1024,
            "cache_key" => "gradle-key-abc123"
          }
        ]
      }

      json_body = Jason.encode!(events_params)
      invalid_signature = "invalid_signature"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", invalid_signature)
        |> post(~p"/webhooks/gradle-cache", json_body)

      assert conn.status == 403
      assert conn.resp_body == "Invalid signature"

      events = ClickHouseRepo.all(from e in CacheEvent, where: e.project_id == ^project.id)
      assert events == []
    end
  end
end
