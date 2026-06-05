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

  # The worker calls `Req.get` with `:into` so the response body
  # arrives in chunks. Drive the callback synthetically with one or
  # more chunks and return the resulting (mutated) `Req.Response`.
  defp stub_req_stream(chunks) when is_list(chunks) do
    expect(Req, :get, fn opts ->
      resp = %Req.Response{status: 200, private: %{}}

      resp =
        Enum.reduce(chunks, resp, fn chunk, acc ->
          {:cont, {_req, acc}} = opts[:into].({:data, chunk}, {opts, acc})
          acc
        end)

      {:ok, resp}
    end)
  end

  defp stub_req_stream(body) when is_binary(body), do: stub_req_stream([body])

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

        resp = %Req.Response{status: 200, private: %{}}
        {:cont, {_req, resp}} = opts[:into].({:data, body}, {opts, resp})
        {:ok, resp}
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

      assert JobLogs.list_for_job(9_910_002) == []
      refute_enqueued(worker: ArchiveLogsWorker, args: %{workflow_job_id: 9_910_002})
    end

    test "skips the archive enqueue when the log came back empty" do
      account = account_fixture()
      enqueue(account, 9_910_003)
      stub_gh_installation_token()

      # Empty 200: Req never invokes `:into` because there's no
      # data chunk. The worker should still finish cleanly without
      # enqueueing the archive.
      expect(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, private: %{}}}
      end)

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_003, account.id)})

      refute_enqueued(worker: ArchiveLogsWorker, args: %{workflow_job_id: 9_910_003})
    end

    test "broadcasts :runner_job_logs_ready so the LiveView refreshes without a manual reload" do
      account = account_fixture()
      enqueue(account, 9_910_020)
      stub_gh_installation_token()

      :ok = Tuist.PubSub.subscribe(JobLogs.topic(9_910_020))

      stub_req_stream("2026-06-02T15:31:03.111111Z hi\n")

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_020, account.id)})

      assert_receive {:runner_job_logs_ready, %{workflow_job_id: 9_910_020}}, 1_000
    end

    test "does not broadcast when the log came back empty" do
      account = account_fixture()
      enqueue(account, 9_910_021)
      stub_gh_installation_token()

      :ok = Tuist.PubSub.subscribe(JobLogs.topic(9_910_021))

      expect(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, private: %{}}}
      end)

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_021, account.id)})

      refute_receive {:runner_job_logs_ready, _}, 100
    end

    test "strips the UTF-8 BOM that prefixes GitHub's Logs API response" do
      account = account_fixture()
      enqueue(account, 9_910_010)
      stub_gh_installation_token()

      stub_req_stream("﻿2026-06-02T15:31:03.111111Z Current runner version: '2.334.0'\n")

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_010, account.id)})

      [line] = JobLogs.list_for_job(9_910_010)
      assert line.message == "Current runner version: '2.334.0'"
      refute line.message =~ "2026-06-02T"
    end

    test "preserves lines that span chunk boundaries when the body arrives in pieces" do
      account = account_fixture()
      enqueue(account, 9_910_020)
      stub_gh_installation_token()

      # Three TCP chunks carving the same payload at awkward
      # offsets (inside the first line's message, inside the next
      # line's timestamp). The worker must stitch the partial
      # tail of each chunk onto the head of the next without
      # losing or splitting any line.
      stub_req_stream([
        "2026-06-02T15:31:03.111111Z First li",
        "ne\n2026-06-02T15:31:03.222222Z Second line\n2026",
        "-06-02T15:31:03.333333Z Third line\n"
      ])

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_020, account.id)})

      lines = JobLogs.list_for_job(9_910_020)
      assert Enum.map(lines, & &1.message) == ["First line", "Second line", "Third line"]
    end

    test "flushes the trailing partial line when the payload doesn't end in a newline" do
      # Defensive: GitHub's payload ends with `\n` today, but the
      # streaming finaliser handles an unterminated last line so a
      # truncated response doesn't silently drop a row.
      account = account_fixture()
      enqueue(account, 9_910_021)
      stub_gh_installation_token()

      stub_req_stream("2026-06-02T15:31:03.111111Z Only line, no trailing newline")

      assert :ok = FetchLogsWorker.perform(%Oban.Job{args: args(9_910_021, account.id)})

      [line] = JobLogs.list_for_job(9_910_021)
      assert line.message == "Only line, no trailing newline"
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
