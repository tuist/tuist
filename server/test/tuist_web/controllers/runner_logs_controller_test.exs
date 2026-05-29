defmodule TuistWeb.RunnerLogsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias TuistWeb.RunnerLogToken

  defp enqueue(account, workflow_job_id) do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "fleet-logs",
        repository: "acme/cli",
        workflow_run_id: workflow_job_id * 10,
        run_attempt: 1,
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef"
      })
  end

  defp post_logs(conn, token, body) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> post("/api/internal/runners/logs", JSON.encode!(body))
  end

  describe "POST /api/internal/runners/logs" do
    test "ingests a batch and flips the job to streaming", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 8_800_001)
      token = RunnerLogToken.sign(8_800_001, account.id)

      conn =
        post_logs(conn, token, %{
          "lines" => [
            %{"n" => 1, "ts" => "2026-05-28T12:00:00Z", "message" => "hello"},
            %{"n" => 2, "ts" => "2026-05-28T12:00:01Z", "message" => "world"}
          ]
        })

      assert response(conn, 202)

      assert Enum.map(JobLogs.list_for_job(8_800_001), & &1.message) == ["hello", "world"]
      assert {:ok, %{log_state: "streaming"}} = Jobs.get_for_account(account.id, 8_800_001)
    end

    test "finalizes the log state on the closing batch", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 8_800_002)
      token = RunnerLogToken.sign(8_800_002, account.id)

      _ = post_logs(conn, token, %{"lines" => [%{"n" => 1, "ts" => "2026-05-28T12:00:00Z", "message" => "a"}]})

      conn =
        post_logs(build_conn(), token, %{
          "lines" => [%{"n" => 2, "ts" => "2026-05-28T12:00:01Z", "message" => "b"}],
          "done" => true
        })

      assert response(conn, 202)
      assert {:ok, %{log_state: "complete", log_line_count: 2}} = Jobs.get_for_account(account.id, 8_800_002)

      assert_enqueued(
        worker: ArchiveLogsWorker,
        args: %{workflow_job_id: 8_800_002, account_id: account.id}
      )
    end

    test "does not enqueue an archive when the stream closes with no lines", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 8_800_004)
      token = RunnerLogToken.sign(8_800_004, account.id)

      conn = post_logs(conn, token, %{"lines" => [], "done" => true})

      assert response(conn, 202)
      refute_enqueued(worker: ArchiveLogsWorker, args: %{workflow_job_id: 8_800_004})
    end

    test "attributes lines from the token, ignoring any client-supplied ids", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 8_800_003)
      token = RunnerLogToken.sign(8_800_003, account.id)

      # A spoofed account_id/workflow_job_id in the body must be ignored.
      conn =
        post_logs(conn, token, %{
          "lines" => [
            %{"n" => 1, "ts" => "2026-05-28T12:00:00Z", "message" => "mine", "account_id" => 999, "workflow_job_id" => 1}
          ]
        })

      assert response(conn, 202)
      assert Enum.map(JobLogs.list_for_job(8_800_003), & &1.message) == ["mine"]
      assert JobLogs.list_for_job(1) == []
    end

    test "rejects an invalid token", %{conn: conn} do
      conn = post_logs(conn, "not-a-valid-token", %{"lines" => []})
      assert json_response(conn, 401)["error"] =~ "invalid"
    end

    test "rejects a missing token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/internal/runners/logs", JSON.encode!(%{"lines" => []}))

      assert json_response(conn, 401)["error"] =~ "token"
    end
  end
end
