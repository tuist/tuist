defmodule Tuist.Runners.Workers.ArchiveLogsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Storage

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

  describe "perform/1" do
    test "gzips the full log, uploads it to S3, and records the archive key" do
      account = account_fixture()
      enqueue(account, 9_900_001)

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: 9_900_001,
            account_id: account.id,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "first"
          },
          %{
            workflow_job_id: 9_900_001,
            account_id: account.id,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "second"
          }
        ])

      expected_key = "runners/#{account.id}/9900001/runner.log.gz"

      expect(Storage, :put_object, fn ^expected_key, gzipped, %{id: account_id} ->
        assert account_id == account.id

        decompressed = :zlib.gunzip(gzipped)
        assert decompressed =~ "first"
        assert decompressed =~ "second"
        :ok
      end)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_001, "account_id" => account.id}
               })

      assert {:ok, %{log_archive_key: ^expected_key}} = Jobs.get_for_account(account.id, 9_900_001)
    end

    test "is a no-op when the job has no captured log lines" do
      account = account_fixture()
      enqueue(account, 9_900_002)

      reject(&Storage.put_object/3)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_002, "account_id" => account.id}
               })

      assert {:ok, %{log_archive_key: ""}} = Jobs.get_for_account(account.id, 9_900_002)
    end

    test "is a no-op when the account no longer exists" do
      reject(&Storage.put_object/3)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_003, "account_id" => -1}
               })
    end
  end
end
