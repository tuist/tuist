defmodule TuistWeb.Webhooks.CacheControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Cache.CASEvent
  alias Tuist.ClickHouseRepo
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
    json_body = JSON.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    {json_body, signature}
  end

  describe "POST /webhooks/cache" do
    test "creates multiple CAS events with valid signature and handles", %{conn: conn, project: project} do
      # Given
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 1024,
            "cas_id" => "abc123"
          },
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "download",
            "size" => 2048,
            "cas_id" => "def456"
          },
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 512,
            "cas_id" => "ghi789"
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "test-cache-node.tuist.dev")
        |> post(~p"/webhooks/cache", body)

      # Then
      assert json_response(conn, 202) == %{}

      # Verify all events were created in database
      events =
        ClickHouseRepo.all(from e in CASEvent, where: e.project_id == ^project.id, order_by: e.size)

      assert length(events) == 3

      [event1, event2, event3] = events

      assert event1.action == "upload"
      assert event1.size == 512
      assert event1.cas_id == "ghi789"
      assert event1.project_id == project.id
      assert event1.cache_endpoint == "test-cache-node.tuist.dev"

      assert event2.action == "upload"
      assert event2.size == 1024
      assert event2.cas_id == "abc123"
      assert event2.project_id == project.id
      assert event2.cache_endpoint == "test-cache-node.tuist.dev"

      assert event3.action == "download"
      assert event3.size == 2048
      assert event3.cas_id == "def456"
      assert event3.project_id == project.id
      assert event3.cache_endpoint == "test-cache-node.tuist.dev"
    end

    # A newer Kura node sends event_id and observed_at_ms alongside the fields
    # the current controller pattern-matches on. The server preserves both
    # when present: event_id becomes the row's identity so a future retry
    # dedupes at the CAS pipeline (buffered path — INSERT-token support is a
    # follow-up), and observed_at_ms becomes inserted_at so the row records
    # the original observation time. Fields remain optional for old Kura.
    test "preserves event_id and observed_at_ms from the producer when present",
         %{conn: conn, project: project} do
      event_id = "01930c0e-6e2a-7a91-9a1c-1f4e5c2d3a4b"
      observed_at_ms = 1_760_000_000_123

      events_params = %{
        "events" => [
          %{
            "event_id" => event_id,
            "observed_at_ms" => observed_at_ms,
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 1024,
            "cas_id" => "abc123-newer-kura"
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "test-cache-node.tuist.dev")
        |> post(~p"/webhooks/cache", body)

      assert json_response(conn, 202) == %{}

      events = ClickHouseRepo.all(from e in CASEvent, where: e.project_id == ^project.id)
      assert length(events) == 1
      [event] = events
      assert event.id == event_id
      assert event.action == "upload"
      assert event.size == 1024
      assert event.cas_id == "abc123-newer-kura"

      {:ok, expected_observed_at} = DateTime.from_unix(observed_at_ms, :millisecond)

      assert NaiveDateTime.compare(
               event.inserted_at,
               expected_observed_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
             ) == :eq
    end

    test "rejects requests with invalid signature", %{conn: conn, project: project} do
      # Given
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 1024,
            "cas_id" => "abc123"
          }
        ]
      }

      json_body = JSON.encode!(events_params)
      invalid_signature = "invalid_signature"

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", invalid_signature)
        |> put_req_header("x-cache-endpoint", "test-cache-node.tuist.dev")
        |> post(~p"/webhooks/cache", json_body)

      # Then
      assert conn.status == 403
      assert conn.resp_body == "Invalid signature"

      # Verify no events were created
      events = ClickHouseRepo.all(from e in CASEvent, where: e.project_id == ^project.id)
      assert events == []
    end

    test "rejects requests without x-cache-endpoint header", %{conn: conn, project: project} do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 1024,
            "cas_id" => "abc123"
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> post(~p"/webhooks/cache", body)

      assert json_response(conn, 400) == %{"error" => "Missing x-cache-endpoint header"}

      events = ClickHouseRepo.all(from e in CASEvent, where: e.project_id == ^project.id)
      assert events == []
    end

    test "rejects requests with empty x-cache-endpoint header", %{conn: conn, project: project} do
      events_params = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "action" => "upload",
            "size" => 1024,
            "cas_id" => "abc123"
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "")
        |> post(~p"/webhooks/cache", body)

      assert json_response(conn, 400) == %{"error" => "Missing x-cache-endpoint header"}

      events = ClickHouseRepo.all(from e in CASEvent, where: e.project_id == ^project.id)
      assert events == []
    end
  end
end
