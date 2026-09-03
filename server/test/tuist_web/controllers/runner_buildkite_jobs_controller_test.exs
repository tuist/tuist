defmodule TuistWeb.RunnerBuildkiteJobsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.RunnerSessions

  @pod_name "tuist-runner-pod-1"

  defp runner_token_stub(pod_name) do
    stub(K8sClient, :create_token_review, fn "valid-token" ->
      {:ok, %{namespace: Environment.runners_namespace(), name: pod_name, uid: "uid-1"}}
    end)
  end

  # Buildkite dispatch opens the session with the execution binding
  # already set: the acquisition token names one job, so unlike the GitHub
  # lane there is nothing to learn from a later webhook.
  defp session(account, workflow_job_id, pod_name, runner_name) do
    {:ok, session} =
      RunnerSessions.open(%{
        workflow_job_id: workflow_job_id,
        executed_workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        pod_name: pod_name,
        runner_name: runner_name,
        started_at: DateTime.utc_now()
      })

    session
  end

  setup do
    %{account: account} = organization_fixture(preload: [:account])
    workflow_job_id = 1_000_000_000_000_123
    %{account: account, workflow_job_id: workflow_job_id}
  end

  describe "POST logs" do
    test "appends the agent's log lines against the pod's job", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id
    } do
      runner_token_stub(@pod_name)
      session(account, workflow_job_id, @pod_name, "runner-1")

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
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/#{@pod_name}/buildkite/logs", %{
          "lines" => ["\e_bk;t=1756900000000\aRunning tests", "All tests passed"],
          "first_line_number" => 1
        })

      assert response(conn, 204)
    end

    test "drops lines for a pod with no open session", %{conn: conn} do
      runner_token_stub(@pod_name)
      reject(&JobLogs.append/1)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/#{@pod_name}/buildkite/logs", %{"lines" => ["x"]})

      assert response(conn, 204)
    end

    test "rejects a body whose lines are not strings", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id
    } do
      runner_token_stub(@pod_name)
      session(account, workflow_job_id, @pod_name, "runner-1")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/#{@pod_name}/buildkite/logs", %{"lines" => [1, 2]})

      assert json_response(conn, 400)["error"] =~ "lines"
    end

    test "refuses a token whose principal is another pod", %{conn: conn} do
      runner_token_stub("some-other-pod")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/#{@pod_name}/buildkite/logs", %{"lines" => ["x"]})

      assert json_response(conn, 401)["error"] == "unauthorized principal"
    end

    test "refuses an unauthenticated request", %{conn: conn} do
      conn = post(conn, "/api/internal/runners/pods/#{@pod_name}/buildkite/logs", %{"lines" => []})

      assert json_response(conn, 401)["error"] == "missing bearer token"
    end
  end

  describe "POST finish" do
    test "reports the job's window and outcome", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id
    } do
      runner_token_stub(@pod_name)
      session(account, workflow_job_id, @pod_name, "runner-1")

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
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/#{@pod_name}/buildkite/finish", %{
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
      workflow_job_id: workflow_job_id
    } do
      runner_token_stub(@pod_name)
      session(account, workflow_job_id, @pod_name, "runner-1")

      expect(Buildkite, :record_job_finished, fn _runner, _account_id, report ->
        assert report.conclusion == "cancelled"
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/#{@pod_name}/buildkite/finish", %{
          "exit_status" => 1,
          "cancelled" => true
        })

      assert response(conn, 204)
    end

    test "fails the request when the window could not be recorded", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id
    } do
      runner_token_stub(@pod_name)
      session(account, workflow_job_id, @pod_name, "runner-1")

      expect(Buildkite, :record_job_finished, fn _runner, _account_id, _report ->
        {:error, :session_execution_write_failed}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/#{@pod_name}/buildkite/finish", %{"exit_status" => 0})

      assert json_response(conn, 500)["error"] == "finish report failed"
    end
  end
end
