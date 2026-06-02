defmodule Tuist.Runners.Workers.FetchLogsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.GitHub.App
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Runners.Workers.FetchLogsWorker
  alias Tuist.VCS

  setup :verify_on_exit!

  defp enqueue(account, workflow_job_id) do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "acme/cli",
        workflow_run_id: workflow_job_id * 10,
        run_attempt: 1,
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef"
      })
  end

  defp args(workflow_job_id, account_id) do
    %{
      "workflow_job_id" => workflow_job_id,
      "account_id" => account_id,
      "installation_id" => 12_345,
      "repository" => "tuist/tuist"
    }
  end

  defp stub_gh_installation_token do
    stub(VCS, :get_github_app_installation_by_installation_id, fn _id ->
      {:ok, %{installation_id: "12345"}}
    end)

    stub(VCS, :installation_api_url, fn _installation -> "https://api.github.com" end)

    stub(App, :get_installation_token, fn _installation, _opts ->
      {:ok, %{token: "ghs_test_token"}}
    end)
  end

  describe "perform/1" do
    test "fetches the log from GitHub, ingests every line, and enqueues the archive worker" do
      account = account_fixture()
      enqueue(account, 9_910_001)
      stub_gh_installation_token()

      body = """
      2026-06-02T15:31:03.111111Z ##[group]Run echo "Hostname: $(hostname)"
      2026-06-02T15:31:03.222222Z Hostname: tuist-tuist-runner-pool-linux-4vcpu-16gb-runner-x
      2026-06-02T15:31:03.333333Z ##[endgroup]
      """

      expect(Req, :get, fn opts ->
        assert opts[:url] ==
                 "https://api.github.com/repos/tuist/tuist/actions/jobs/9910001/logs"

        assert {"Authorization", "Bearer ghs_test_token"} in opts[:headers]
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_001, account.id)})

      lines = JobLogs.list_for_job(9_910_001)
      assert length(lines) == 3
      assert Enum.at(lines, 0).message =~ "##[group]Run echo"
      assert Enum.at(lines, 1).message =~ "Hostname: tuist-tuist-runner-pool"
      assert Enum.at(lines, 2).message =~ "##[endgroup]"

      assert_enqueued(
        worker: ArchiveLogsWorker,
        args: %{workflow_job_id: 9_910_001, account_id: account.id}
      )

      assert {:ok, %{log_state: "complete", log_line_count: 3}} =
               Jobs.get_for_account(account.id, 9_910_001)
    end

    test "returns the error so Oban retries when GitHub hasn't published the log yet (404)" do
      account = account_fixture()
      enqueue(account, 9_910_002)
      stub_gh_installation_token()

      expect(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 404, body: ""}}
      end)

      assert {:error, :log_not_ready_yet} =
               FetchLogsWorker.perform(%Oban.Job{args: args(9_910_002, account.id)})

      # No lines stored, log_state stays at default (still "streaming"-or-empty,
      # never advanced to "complete").
      assert JobLogs.list_for_job(9_910_002) == []
      refute_enqueued(worker: ArchiveLogsWorker, args: %{workflow_job_id: 9_910_002})
    end

    test "skips the archive enqueue when the log came back empty" do
      account = account_fixture()
      enqueue(account, 9_910_003)
      stub_gh_installation_token()

      expect(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_003, account.id)})

      refute_enqueued(worker: ArchiveLogsWorker, args: %{workflow_job_id: 9_910_003})

      assert {:ok, %{log_state: "complete", log_line_count: 0}} =
               Jobs.get_for_account(account.id, 9_910_003)
    end

    test "is a no-op when the GitHub App installation has been uninstalled" do
      account = account_fixture()
      enqueue(account, 9_910_004)

      stub(VCS, :get_github_app_installation_by_installation_id, fn _ -> {:error, :not_found} end)
      reject(&Req.get/1)

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_004, account.id)})

      assert JobLogs.list_for_job(9_910_004) == []
    end
  end
end
