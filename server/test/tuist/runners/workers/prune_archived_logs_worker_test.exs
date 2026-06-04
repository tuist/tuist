defmodule Tuist.Runners.Workers.PruneArchivedLogsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Runners.Workers.PruneArchivedLogsWorker
  alias Tuist.Storage

  setup :verify_on_exit!

  defp seed_completed_job(account, workflow_job_id, archived_at) do
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

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
    :ok = Jobs.record_running(workflow_job_id, "runner-x")
    {:ok, _} = Jobs.complete(workflow_job_id, "success")
    :ok = Jobs.set_log_archived_at(workflow_job_id, archived_at)
  end

  describe "perform/1" do
    test "deletes the S3 object and clears the timestamp for archives older than 90 days" do
      account = account_fixture()
      old = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
      key = ArchiveLogsWorker.archive_key(account.id, 8_500_001)

      seed_completed_job(account, 8_500_001, old)

      expect(Storage, :delete_object, fn ^key, %{id: account_id} ->
        assert account_id == account.id
        :ok
      end)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})
      assert {:ok, %{log_archived_at: nil}} = Jobs.get_for_account(account.id, 8_500_001)
    end

    test "leaves archives younger than 90 days alone" do
      account = account_fixture()
      recent = DateTime.add(DateTime.utc_now(), -10 * 24 * 60 * 60, :second)

      seed_completed_job(account, 8_500_002, recent)

      reject(&Storage.delete_object/2)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})
      assert {:ok, %{log_archived_at: ^recent}} = Jobs.get_for_account(account.id, 8_500_002)
    end

    test "keeps the timestamp when the S3 delete errors, so tomorrow's run retries" do
      account = account_fixture()
      old = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
      key = ArchiveLogsWorker.archive_key(account.id, 8_500_003)

      seed_completed_job(account, 8_500_003, old)

      expect(Storage, :delete_object, fn ^key, _account ->
        {:error, :s3_unavailable}
      end)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})
      assert {:ok, %{log_archived_at: ^old}} = Jobs.get_for_account(account.id, 8_500_003)
    end

    test "continues past a per-archive failure so one bad account doesn't block the rest" do
      account = account_fixture()
      old = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
      bad_key = ArchiveLogsWorker.archive_key(account.id, 8_500_004)

      seed_completed_job(account, 8_500_004, old)
      seed_completed_job(account, 8_500_005, old)

      expect(Storage, :delete_object, 2, fn key, _account ->
        if key == bad_key, do: {:error, :s3_unavailable}, else: :ok
      end)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})

      assert {:ok, %{log_archived_at: ^old}} = Jobs.get_for_account(account.id, 8_500_004)
      assert {:ok, %{log_archived_at: nil}} = Jobs.get_for_account(account.id, 8_500_005)
    end
  end
end
