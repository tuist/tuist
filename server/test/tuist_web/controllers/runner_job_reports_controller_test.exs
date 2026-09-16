defmodule TuistWeb.RunnerJobReportsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.Job
  alias Tuist.Runners.Buildkite.ReportToken
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.JobReportToken
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.WorkflowJob

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

  test "GitLab reports use the assigned job and parse section markers", %{conn: conn, account: account} do
    mapping =
      Repo.insert!(%Tuist.Runners.GitLab.Job{
        account_id: account.id,
        url: "https://gitlab.com",
        job_id: 42,
        project_path: "acme/mobile",
        pipeline_id: 90
      })

    token = JobReportToken.mint(mapping)

    expect(JobLogs, :append, fn [line] ->
      assert line.workflow_job_id == mapping.workflow_job_id
      assert line.account_id == account.id
      assert line.message == "Running tests"
      assert DateTime.to_unix(line.ts) == 1_756_900_000
      :ok
    end)

    conn =
      conn
      |> authed(token)
      |> post("/api/internal/runners/jobs/logs", %{lines: ["section_start:1756900000:script\rRunning tests"]})

    assert response(conn, 204)
  end

  test "GitLab outcomes route to its context with server-observed billing", %{conn: conn, account: account} do
    mapping =
      Repo.insert!(%Tuist.Runners.GitLab.Job{
        account_id: account.id,
        url: "https://gitlab.com",
        job_id: 42,
        project_path: "acme/mobile",
        pipeline_id: 90
      })

    session(account, mapping.workflow_job_id, "gitlab-runner")
    token = JobReportToken.mint(mapping)

    expect(Tuist.Runners.GitLab, :record_job_finished, fn "gitlab-runner", account_id, report ->
      assert account_id == account.id
      assert report == %{workflow_job_id: mapping.workflow_job_id, conclusion: "failure"}
      :ok
    end)

    conn =
      conn |> authed(token) |> post("/api/internal/runners/jobs/finish", %{exit_status: 7, started_at: 0, finished_at: 1})

    assert response(conn, 204)
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
        |> post("/api/internal/runners/jobs/logs", %{
          "lines" => ["\e_bk;t=1756900000000\aRunning tests", "All tests passed"],
          "first_line_number" => 1
        })

      assert response(conn, 204)
    end

    test "rejects a body whose lines are not strings", %{conn: conn, token: token} do
      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/logs", %{"lines" => [1, 2]})

      assert json_response(conn, 400)["error"] =~ "lines"
    end

    test "refuses a forged report token", %{conn: conn} do
      conn =
        conn
        |> authed("not-a-real-token")
        |> post("/api/internal/runners/jobs/logs", %{"lines" => ["x"]})

      assert json_response(conn, 401)["error"] == "invalid report token"
    end

    test "refuses an unauthenticated request", %{conn: conn} do
      conn = post(conn, "/api/internal/runners/jobs/logs", %{"lines" => []})

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
        |> post("/api/internal/runners/jobs/logs", %{"lines" => ["x"]})

      assert json_response(conn, 401)["error"] == "invalid report token"
    end
  end

  describe "POST logs bounds" do
    test "refuses lines past the per-job ceiling", %{conn: conn, token: token} do
      # The byte cap bounds one request; without a ceiling on the line
      # number the same token could keep appending fresh batches.
      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/logs", %{
          "lines" => ["x"],
          "first_line_number" => 1_000_001
        })

      assert json_response(conn, 400)["error"] =~ "first_line_number"
    end

    test "refuses logs once the job has been settled past the grace window", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id,
      token: token
    } do
      long_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

      Repo.insert!(%WorkflowJob{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        provider: "buildkite",
        status: "completed",
        fleet_name: "linux-amd64",
        enqueued_at: long_ago,
        completed_at: long_ago
      })

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/logs", %{"lines" => ["x"], "first_line_number" => 1})

      assert json_response(conn, 410)["error"] =~ "no longer accepting"
    end

    test "still accepts the upload that follows a job's finish report", %{
      conn: conn,
      account: account,
      workflow_job_id: workflow_job_id,
      token: token
    } do
      Repo.insert!(%WorkflowJob{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        provider: "buildkite",
        status: "completed",
        fleet_name: "linux-amd64",
        enqueued_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      expect(JobLogs, :append, fn _lines -> :ok end)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/logs", %{"lines" => ["x"], "first_line_number" => 1})

      assert response(conn, 204)
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
        # The window is measured server-side, so timestamps in the body
        # are not carried into the report at all.
        refute Map.has_key?(report, :started_at)
        refute Map.has_key?(report, :ended_at)
        :ok
      end)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/finish", %{
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
        |> post("/api/internal/runners/jobs/finish", %{
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
        |> post("/api/internal/runners/jobs/finish", %{"exit_status" => 0})

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
        |> post("/api/internal/runners/jobs/finish", %{"exit_status" => 0})

      assert json_response(conn, 500)["error"] == "finish report failed"
    end
  end

  describe "POST cache" do
    setup %{account: account} do
      mapping =
        Repo.insert!(%Tuist.Runners.GitLab.Job{
          account_id: account.id,
          url: "https://gitlab.com",
          job_id: 42,
          project_path: "acme/mobile",
          pipeline_id: 90
        })

      payload = %{"job_info" => %{"project_id" => 123}, "git_info" => %{"protected" => true}}
      %{mapping: mapping, scoped_token: JobReportToken.mint(mapping, payload)}
    end

    test "returns presigned URLs scoped to the token's account, project and ref", %{
      conn: conn,
      account: account,
      scoped_token: token
    } do
      expected_key = "runner-gitlab-cache/#{account.name}/123/protected/gems"

      expect(Tuist.Storage, :generate_download_url, fn ^expected_key, _account, opts ->
        assert opts[:expires_in] == 600
        "https://storage.example.com/#{expected_key}?signature=get"
      end)

      expect(Tuist.Storage, :generate_upload_url, fn ^expected_key, _account, _opts ->
        "https://storage.example.com/#{expected_key}?signature=put"
      end)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/cache", %{"object_name" => "project/123/gems", "expires_in" => 600})

      assert json_response(conn, 200) == %{
               "download_url" => "https://storage.example.com/#{expected_key}?signature=get",
               "upload_url" => "https://storage.example.com/#{expected_key}?signature=put"
             }
    end

    test "a token minted without a cache scope runs without a remote cache", %{conn: conn, mapping: mapping} do
      reject(&Tuist.Storage.generate_upload_url/3)

      conn =
        conn
        |> authed(JobReportToken.mint(mapping))
        |> post("/api/internal/runners/jobs/cache", %{"object_name" => "project/123/gems"})

      assert json_response(conn, 404)["error"] == "cache unavailable"
    end

    test "a Buildkite token cannot mint GitLab cache URLs", %{conn: conn, token: token} do
      reject(&Tuist.Storage.generate_upload_url/3)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/cache", %{"object_name" => "project/123/gems"})

      assert json_response(conn, 404)["error"] == "cache unavailable"
    end

    test "rejects another project's object", %{conn: conn, scoped_token: token} do
      reject(&Tuist.Storage.generate_upload_url/3)

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/cache", %{"object_name" => "project/999/gems"})

      assert json_response(conn, 400)["error"] == "invalid object_name"
    end

    test "a settled job cannot mint URLs", %{conn: conn, account: account, mapping: mapping, scoped_token: token} do
      reject(&Tuist.Storage.generate_upload_url/3)
      now = DateTime.utc_now()

      Repo.insert!(%WorkflowJob{
        workflow_job_id: mapping.workflow_job_id,
        account_id: account.id,
        provider: "gitlab",
        status: "completed",
        fleet_name: "linux-amd64",
        enqueued_at: now,
        completed_at: now
      })

      conn =
        conn
        |> authed(token)
        |> post("/api/internal/runners/jobs/cache", %{"object_name" => "project/123/gems"})

      assert json_response(conn, 410)["error"] =~ "no longer accepting"
    end

    test "requires a report token", %{conn: conn} do
      conn = post(conn, "/api/internal/runners/jobs/cache", %{"object_name" => "project/123/gems"})
      assert json_response(conn, 401)["error"] == "missing bearer token"
    end
  end
end
