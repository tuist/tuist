defmodule Tuist.Runners.Workers.PruneArchivedLogsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.PruneArchivedLogsWorker
  alias Tuist.Storage

  setup :verify_on_exit!

  defp seed_completed_job(account, workflow_job_id, completed_at, opts) do
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
        head_sha: "deadbeef",
        # Carry an explicit `enqueued_at` so the row's lifecycle
        # timestamps look plausible for an old run.
        enqueued_at: DateTime.add(completed_at, -3600, :second)
      })

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.add(completed_at, -1800, :second))
    :ok = Jobs.record_running(workflow_job_id, "runner-x")
    {:ok, _} = Jobs.complete(workflow_job_id, "success")

    # Force completed_at to the value the test wants. `complete/2`
    # stamps `now`, so we follow up with an INSERT carrying the
    # backdated value.
    if archive_key = Keyword.get(opts, :archive_key) do
      :ok = Jobs.set_log_archive_key(workflow_job_id, archive_key)
    end

    backdate_completed_at(account.id, workflow_job_id, completed_at)
  end

  defp backdate_completed_at(account_id, workflow_job_id, completed_at) do
    {:ok, job} = Jobs.get_for_account(account_id, workflow_job_id)

    row =
      job
      |> Map.from_struct()
      |> Map.delete(:__meta__)
      |> Map.merge(%{completed_at: completed_at, updated_at: DateTime.utc_now()})

    Tuist.IngestRepo.insert_all(Tuist.Runners.Job, [row])
    :ok
  end

  describe "perform/1" do
    test "deletes the S3 object and clears the key for archives older than 90 days" do
      account = account_fixture()
      old = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
      key = "runners/#{account.id}/8500001/runner.log.gz"

      seed_completed_job(account, 8_500_001, old, archive_key: key)

      expect(Storage, :delete_object, fn ^key, %{id: account_id} ->
        assert account_id == account.id
        :ok
      end)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})
      assert {:ok, %{log_archive_key: ""}} = Jobs.get_for_account(account.id, 8_500_001)
    end

    test "leaves archives younger than 90 days alone" do
      account = account_fixture()
      recent = DateTime.add(DateTime.utc_now(), -10 * 24 * 60 * 60, :second)
      key = "runners/#{account.id}/8500002/runner.log.gz"

      seed_completed_job(account, 8_500_002, recent, archive_key: key)

      reject(&Storage.delete_object/2)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})
      assert {:ok, %{log_archive_key: ^key}} = Jobs.get_for_account(account.id, 8_500_002)
    end

    test "keeps the key when the S3 delete errors, so tomorrow's run retries" do
      account = account_fixture()
      old = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
      key = "runners/#{account.id}/8500003/runner.log.gz"

      seed_completed_job(account, 8_500_003, old, archive_key: key)

      expect(Storage, :delete_object, fn ^key, _account ->
        {:error, :s3_unavailable}
      end)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})
      assert {:ok, %{log_archive_key: ^key}} = Jobs.get_for_account(account.id, 8_500_003)
    end

    test "continues past a per-archive failure so one bad account doesn't block the rest" do
      account = account_fixture()
      old = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
      bad_key = "runners/#{account.id}/8500004/runner.log.gz"
      good_key = "runners/#{account.id}/8500005/runner.log.gz"

      seed_completed_job(account, 8_500_004, old, archive_key: bad_key)
      seed_completed_job(account, 8_500_005, old, archive_key: good_key)

      expect(Storage, :delete_object, 2, fn key, _account ->
        if key == bad_key, do: {:error, :s3_unavailable}, else: :ok
      end)

      assert :ok = PruneArchivedLogsWorker.perform(%Oban.Job{args: %{}})

      assert {:ok, %{log_archive_key: ^bad_key}} = Jobs.get_for_account(account.id, 8_500_004)
      assert {:ok, %{log_archive_key: ""}} = Jobs.get_for_account(account.id, 8_500_005)
    end
  end
end
