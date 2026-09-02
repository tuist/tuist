defmodule TuistWeb.Webhooks.ReapiCacheControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.ReapiCache.CacheEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @cache_api_key "test-cache-api-key"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    project =
      ProjectsFixtures.project_fixture(
        account_id: user.account.id,
        build_system: :bazel
      )

    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)

    %{conn: conn, project: project}
  end

  defp sign_request(body) do
    json_body = JSON.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    {json_body, signature}
  end

  describe "POST /webhooks/reapi-cache" do
    test "accepts an empty event batch", %{conn: conn} do
      {body, signature} = sign_request(%{"events" => []})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/reapi-cache", body)

      assert json_response(conn, 202) == %{"accepted" => 0, "rejected" => 0}
    end

    test "creates action-cache and content-addressable-storage events with a valid signature", %{
      conn: conn,
      project: project
    } do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "client_kind" => "bazel",
            "operation" => "action_cache",
            "outcome" => "hit",
            "action_digest" => "action-hit",
            "size" => 2_048,
            "duration_ms" => 12,
            "observed_at_ms" => 1_700_000_000_123,
            "invocation_id" => "invocation-1",
            "action_mnemonic" => "SwiftCompile",
            "target_label" => "//App:App",
            "configuration_id" => "config-1"
          },
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "client_kind" => "bazel",
            "operation" => "action_cache",
            "outcome" => "write",
            "action_digest" => "action-write",
            "size" => 1_024,
            "duration_ms" => 20
          },
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "client_kind" => "bazel",
            "operation" => "cas",
            "outcome" => "hit",
            "action_digest" => "content-digest",
            "size" => 512,
            "duration_ms" => 7,
            "invocation_id" => "invocation-1"
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/reapi-cache", body)

      assert json_response(conn, 202) == %{"accepted" => 3, "rejected" => 0}

      events =
        ClickHouseRepo.all(from(e in CacheEvent, where: e.project_id == ^project.id, order_by: e.size))

      assert [content, write, hit] = events
      assert content.operation == "cas"
      assert content.outcome == "hit"
      assert content.action_digest == "content-digest"
      assert content.size == 512
      assert write.outcome == "write"
      assert write.size == 1_024
      assert write.invocation_id == ""
      assert hit.outcome == "hit"
      assert hit.action_digest == "action-hit"
      assert hit.duration_ms == 12

      assert DateTime.compare(hit.observed_at, DateTime.from_unix!(1_700_000_000_123, :millisecond)) == :eq

      assert hit.invocation_id == "invocation-1"
      assert hit.target_label == "//App:App"
      assert hit.cache_endpoint == "cache.tuist.dev"
    end

    test "ignores non-Bazel cache events", %{conn: conn, project: project} do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "client_kind" => "xcode",
            "operation" => "cas",
            "outcome" => "hit",
            "action_digest" => "content-digest",
            "size" => 512,
            "duration_ms" => 7
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/reapi-cache", body)

      assert json_response(conn, 202) == %{"accepted" => 0, "rejected" => 0}
      assert ClickHouseRepo.all(from(e in CacheEvent, where: e.project_id == ^project.id)) == []
    end

    test "rejects requests with an invalid signature", %{conn: conn, project: project} do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "client_kind" => "bazel",
            "operation" => "action_cache",
            "outcome" => "miss",
            "action_digest" => "action-miss",
            "size" => 0,
            "duration_ms" => 4
          }
        ]
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", "invalid-signature")
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/reapi-cache", JSON.encode!(events_params))

      assert conn.status == 403
      assert conn.resp_body == "Invalid signature"
      assert ClickHouseRepo.all(from(e in CacheEvent, where: e.project_id == ^project.id)) == []
    end

    test "rejects requests without a cache endpoint", %{conn: conn, project: project} do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "client_kind" => "bazel",
            "operation" => "action_cache",
            "outcome" => "miss",
            "action_digest" => "action-miss",
            "size" => 0,
            "duration_ms" => 4
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> post(~p"/webhooks/reapi-cache", body)

      assert json_response(conn, 400) == %{"error" => "Missing x-cache-endpoint header"}
      assert ClickHouseRepo.all(from(e in CacheEvent, where: e.project_id == ^project.id)) == []
    end
  end
end
