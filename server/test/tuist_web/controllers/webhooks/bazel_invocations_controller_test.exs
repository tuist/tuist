defmodule TuistWeb.Webhooks.BazelInvocationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Bazel
  alias Tuist.Bazel.Invocation
  alias Tuist.ClickHouseRepo
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

  describe "POST /webhooks/bazel-invocations" do
    test "stores completed Bazel invocations with a valid signature", %{conn: conn, project: project} do
      body = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "invocation_id" => "invocation-1",
            "command" => "test",
            "bazel_version" => "9.1.0",
            "cpu_time_ms" => 1_250,
            "actions_created" => 11,
            "actions_executed" => 10,
            "targets_configured" => 4,
            "packages_loaded" => 2,
            "build_timeline_duration_ms" => 15_000,
            "build_timeline_lanes" => ["Loading and analysis", "Execution lane 1"],
            "build_timeline_span_lanes" => [0, 1],
            "build_timeline_span_start_ms" => [0, 500],
            "build_timeline_span_durations_ms" => [500, 1_000],
            "build_timeline_span_categories" => ["analysis", "execution"],
            "build_timeline_span_descriptions" => ["Loading and analysis", "Compile //app:app"],
            "critical_path_duration_ms" => 1_000,
            "critical_path_action_descriptions" => ["Compile //app:app"],
            "critical_path_action_durations_ms" => [1_000],
            "logs" => [
              %{
                "sequence_number" => 6,
                "stream" => "stderr",
                "message" => "failed at /Users/developer/app with token=secret-value",
                "observed_at_ms" => 1_700_000_014_000
              }
            ],
            "status" => "success",
            "exit_code" => 0,
            "started_at_ms" => 1_700_000_000_000,
            "finished_at_ms" => 1_700_000_015_000
          }
        ]
      }

      {json_body, signature} = sign_request(body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{"accepted" => 1, "rejected" => 0}

      [invocation] =
        ClickHouseRepo.all(from(i in Invocation, where: i.project_id == ^project.id))

      assert invocation.invocation_id == "invocation-1"
      assert invocation.command == "test"
      assert invocation.status == "success"
      assert invocation.exit_code == 0
      assert invocation.duration_ms == 15_000
      assert invocation.bazel_version == "9.1.0"
      assert invocation.cpu_time_ms == 1_250
      assert invocation.actions_created == 11
      assert invocation.actions_executed == 10
      assert invocation.targets_configured == 4
      assert invocation.packages_loaded == 2
      assert invocation.build_timeline_lanes == ["Loading and analysis", "Execution lane 1"]
      assert invocation.build_timeline_span_descriptions == ["Loading and analysis", "Compile //app:app"]
      assert invocation.critical_path_action_descriptions == ["Compile //app:app"]
      assert invocation.cache_endpoint == "cache.tuist.dev"

      [log] = project.id |> Bazel.list_invocation_logs("invocation-1") |> elem(0)
      assert log.sequence_number == 6
      assert log.stream == "stderr"
      assert log.message == "failed at <LOCAL_PATH> with token=<REDACTED>"
    end

    test "does not store invalid invocation payloads", %{conn: conn, project: project} do
      body = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "invocation_id" => "invocation-1",
            "command" => "build",
            "status" => "unknown",
            "exit_code" => 0,
            "started_at_ms" => 1_700_000_000_000,
            "finished_at_ms" => 1_700_000_015_000
          }
        ]
      }

      {json_body, signature} = sign_request(body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{"accepted" => 0, "rejected" => 1}
      assert ClickHouseRepo.all(from(i in Invocation, where: i.project_id == ^project.id)) == []
    end

    test "does not store diagnostics with mismatched timeline arrays", %{conn: conn, project: project} do
      body = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "invocation_id" => "invocation-1",
            "command" => "build",
            "status" => "success",
            "exit_code" => 0,
            "started_at_ms" => 1_700_000_000_000,
            "finished_at_ms" => 1_700_000_015_000,
            "build_timeline_lanes" => ["Execution lane 1"],
            "build_timeline_span_lanes" => [0],
            "build_timeline_span_start_ms" => []
          }
        ]
      }

      {json_body, signature} = sign_request(body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{"accepted" => 0, "rejected" => 1}
      assert ClickHouseRepo.all(from(i in Invocation, where: i.project_id == ^project.id)) == []
    end

    test "does not store invocation logs above the aggregate size limit", %{conn: conn, project: project} do
      body = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "invocation_id" => "invocation-1",
            "command" => "build",
            "status" => "success",
            "exit_code" => 0,
            "started_at_ms" => 1_700_000_000_000,
            "finished_at_ms" => 1_700_000_015_000,
            "logs" =>
              Enum.map(0..16, fn sequence_number ->
                %{
                  "sequence_number" => sequence_number,
                  "stream" => "stdout",
                  "message" => String.duplicate("a", 2 * 1_024),
                  "observed_at_ms" => 1_700_000_014_000
                }
              end)
          }
        ]
      }

      {json_body, signature} = sign_request(body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{"accepted" => 0, "rejected" => 1}
      assert ClickHouseRepo.all(from(i in Invocation, where: i.project_id == ^project.id)) == []
    end

    test "does not store invocations with implausible future timestamps", %{conn: conn, project: project} do
      future_timestamp_ms =
        DateTime.utc_now()
        |> DateTime.add(2, :hour)
        |> DateTime.to_unix(:millisecond)

      body = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "invocation_id" => "invocation-1",
            "command" => "build",
            "status" => "success",
            "exit_code" => 0,
            "started_at_ms" => future_timestamp_ms,
            "finished_at_ms" => future_timestamp_ms
          }
        ]
      }

      {json_body, signature} = sign_request(body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{"accepted" => 0, "rejected" => 1}
      assert ClickHouseRepo.all(from(i in Invocation, where: i.project_id == ^project.id)) == []
    end

    test "accepts a bounded prefix from legacy batches above the compatibility limit", %{
      conn: conn,
      project: project
    } do
      body = %{
        "events" =>
          Enum.map(0..100, fn index ->
            %{
              "account_handle" => project.account.name,
              "project_handle" => project.name,
              "invocation_id" => "invocation-#{index}",
              "command" => "build",
              "status" => "success",
              "exit_code" => 0,
              "started_at_ms" => 1_700_000_000_000,
              "finished_at_ms" => 1_700_000_015_000
            }
          end)
      }

      {json_body, signature} = sign_request(body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-cache-signature", signature)
        |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{"accepted" => 100, "rejected" => 1}
      assert ClickHouseRepo.aggregate(from(i in Invocation, where: i.project_id == ^project.id), :count) == 100
    end
  end

  defp sign_request(body) do
    json_body = JSON.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    {json_body, signature}
  end
end
