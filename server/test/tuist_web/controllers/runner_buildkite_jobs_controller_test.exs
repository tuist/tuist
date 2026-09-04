defmodule TuistWeb.RunnerBuildkiteJobsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.Job
  alias Tuist.Runners.Buildkite.ReportToken
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.RunnerSessions

  setup do
    %{account: account} = organization_fixture(preload: [:account])

    {:ok, job} =
      %Job{}
      |> Job.changeset(%{
        job_uuid: Ecto.UUID.generate(),
        account_id: account.id,
        organization_slug: "acme",
        pipeline_slug: "ios"
      })
      |> Repo.insert(returning: true)

    token = ReportToken.mint(%{workflow_job_id: job.workflow_job_id, account_id: account.id})

    %{account: account, workflow_job_id: job.workflow_job_id, token: token}
  end

  # Buildkite dispatch opens the session with the execution binding already
  # set: the acquisition token names one job, so unlike the GitHub lane
  # there is nothing to learn from a later webhook.
  defp session(account, workflow_job_id, runner_name) do
    {:ok, session} =
      RunnerSessions.open(%{
        workflow_job_id: workflow_job_id,
        executed_workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        pod_name: "tuist-runner-pod-1",
        runner_name: runner_name,
        started_at: DateTime.utc_now()
      })

    session
  end

  defp authed(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  describe "POST logs" do
    test "appends the agent's log lines against the token's job", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id,
      token: token
    } do
      expect(JobLogs, :append, fn lines ->
        assert [first, second] = lines
        assert first.workflow_job_id == workflow_job_id
        assert first.account_id == account.id
        assert first.line_number == 1
        assert first.message == "Running tests"
        assert second.line_number == 2
        :ok
      end)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/buildkite/logs", %{
          "lines" => ["\e_bk;t=1756900000000\aRunning tests", "All tests passed"],
          "first_line_number" => 1
        })

      assert response(conn, 204)
    end

    test "rejects a body whose lines are not strings", %{conn: conn, token: token} do
      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/buildkite/logs", %{"lines" => [1, 2]})

      assert json_response(conn, 400)["error"] =~ "lines"
    end

    test "refuses a forged report token", %{conn: conn} do
      conn =
        conn
        |> authed("not-a-real-token")
        |> post("/api/internal/runners/buildkite/logs", %{"lines" => ["x"]})

      assert json_response(conn, 401)["error"] == "invalid report token"
    end

    test "refuses an unauthenticated request", %{conn: conn} do
      conn = post(conn, "/api/internal/runners/buildkite/logs", %{"lines" => []})

      assert json_response(conn, 401)["error"] == "missing bearer token"
    end

    test "refuses a token whose job no longer exists", %{conn: conn, account: account} do
      # A signature alone is not enough: the job it names has to still be a
      # Buildkite job of that account, or the ingest would key rows on a
      # job nothing owns.
      token = ReportToken.mint(%{workflow_job_id: 1_000_000_000_000_999, account_id: account.id})

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/buildkite/logs", %{"lines" => ["x"]})

      assert json_response(conn, 401)["error"] == "invalid report token"
    end
  end

  describe "POST finish" do
    test "reports the job's window and outcome", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id,
      token: token
    } do
      session(account, workflow_job_id, "runner-1")

      expect(Buildkite, :record_job_finished, fn "runner-1", account_id, report ->
        assert account_id == account.id
        assert report.workflow_job_id == workflow_job_id
        assert report.conclusion == "success"
        assert report.started_at == DateTime.from_unix!(1_750_684_800)
        assert report.ended_at == DateTime.from_unix!(1_750_684_860)
        :ok
      end)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/buildkite/finish", %{
          "exit_status" => 0,
          "cancelled" => false,
          "started_at" => 1_750_684_800,
          "finished_at" => 1_750_684_860
        })

      assert response(conn, 204)
    end

    test "reports a cancelled job as cancelled rather than failed", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id,
      token: token
    } do
      session(account, workflow_job_id, "runner-1")

      expect(Buildkite, :record_job_finished, fn _runner, _account_id, report ->
        assert report.conclusion == "cancelled"
        :ok
      end)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/buildkite/finish", %{
          "exit_status" => 1,
          "cancelled" => true
        })

      assert response(conn, 204)
    end

    test "accepts a duplicate report once the session is closed", %{conn: conn, token: token} do
      # No open session: the job is settled, so a retried report is not
      # something the hook should keep retrying.
      reject(&Buildkite.record_job_finished/3)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/buildkite/finish", %{"exit_status" => 0})

      assert response(conn, 204)
    end

    test "fails the request when the window could not be recorded", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id,
      token: token
    } do
      session(account, workflow_job_id, "runner-1")

      expect(Buildkite, :record_job_finished, fn _runner, _account_id, _report ->
        {:error, :session_execution_write_failed}
      end)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/buildkite/finish", %{"exit_status" => 0})

      assert json_response(conn, 500)["error"] == "finish report failed"
    end
  end
end
