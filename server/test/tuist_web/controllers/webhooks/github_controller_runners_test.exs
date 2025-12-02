defmodule TuistWeb.Webhooks.GitHubControllerRunnersTest do
  use TuistTestSupport.Cases.DataCase

  import ExUnit.CaptureLog

  alias TuistTestSupport.Fixtures.RunnersFixtures
  alias TuistWeb.Webhooks.GitHubController

  describe "workflow_job webhook with capacity management" do
    setup do
      runner_org = RunnersFixtures.runner_organization_fixture(max_concurrent_jobs: 2)

      payload = %{
        "action" => "queued",
        "workflow_job" => %{
          "id" => 123_456_789,
          "run_id" => 987_654_321,
          "labels" => ["tuist-runners"],
          "html_url" => "https://github.com/org/repo/actions/runs/123/jobs/456",
          "repository_full_name" => "org/repo"
        },
        "organization" => %{
          "login" => "test-org"
        },
        "installation" => %{
          "id" => runner_org.github_app_installation_id
        }
      }

      conn = Plug.Conn.put_req_header(Phoenix.ConnTest.build_conn(), "x-github-event", "workflow_job")

      %{conn: conn, runner_org: runner_org, payload: payload}
    end

    test "creates job when organization has capacity", %{conn: conn, payload: payload, runner_org: runner_org} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Organization has capacity (0/2 jobs)
        conn = GitHubController.handle(conn, payload)

        assert conn.status == 200

        # Job should be created and worker enqueued
        job = Tuist.Runners.get_runner_job_by_github_job_id(123_456_789)
        assert job
        assert job.organization_id == runner_org.id

        assert_enqueued(worker: Tuist.Runners.Workers.SpawnRunnerWorker, args: %{job_id: job.id})
      end)
    end

    test "creates job when organization is under capacity limit", %{conn: conn, payload: payload, runner_org: runner_org} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Create one existing active job (1/2)
        RunnersFixtures.runner_job_fixture(organization: runner_org, status: :running)

        conn = GitHubController.handle(conn, payload)

        assert conn.status == 200

        job = Tuist.Runners.get_runner_job_by_github_job_id(123_456_789)
        assert job
      end)
    end

    test "rejects job when organization is at capacity", %{conn: conn, payload: payload, runner_org: runner_org} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Create two active jobs to reach capacity (2/2)
        RunnersFixtures.runner_job_fixture(organization: runner_org, status: :running)
        RunnersFixtures.runner_job_fixture(organization: runner_org, status: :spawning)

        capture_log(fn ->
          conn = GitHubController.handle(conn, payload)

          assert conn.status == 200

          # Job should NOT be created
          job = Tuist.Runners.get_runner_job_by_github_job_id(123_456_789)
          assert job == nil
        end)
      end)
    end

    test "allows unlimited jobs when max_concurrent_jobs is nil", %{conn: conn, payload: payload} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        unlimited_org = RunnersFixtures.runner_organization_fixture(max_concurrent_jobs: nil)

        # Create many active jobs
        for _ <- 1..10 do
          RunnersFixtures.runner_job_fixture(organization: unlimited_org, status: :running)
        end

        payload = put_in(payload, ["installation", "id"], unlimited_org.github_app_installation_id)

        conn = GitHubController.handle(conn, payload)

        assert conn.status == 200

        job = Tuist.Runners.get_runner_job_by_github_job_id(123_456_789)
        assert job
      end)
    end

    test "only counts active jobs toward capacity limit", %{conn: conn, payload: payload, runner_org: runner_org} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Create completed/failed jobs (should not count)
        RunnersFixtures.runner_job_fixture(organization: runner_org, status: :completed)
        RunnersFixtures.runner_job_fixture(organization: runner_org, status: :failed)
        RunnersFixtures.runner_job_fixture(organization: runner_org, status: :cancelled)

        # Create one active job (1/2)
        RunnersFixtures.runner_job_fixture(organization: runner_org, status: :running)

        conn = GitHubController.handle(conn, payload)

        assert conn.status == 200

        # Should be created because only 1 active job exists
        job = Tuist.Runners.get_runner_job_by_github_job_id(123_456_789)
        assert job
      end)
    end
  end
end
