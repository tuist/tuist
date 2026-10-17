defmodule Tuist.Runners.Workers.PruneRetentionOverridesWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Workers.PruneArchivedLogsWorker
  alias Tuist.Runners.Workers.PruneRetentionOverridesWorker

  setup :verify_on_exit!

  test "deletes only the account's expired logs and metrics, then queues archive cleanup" do
    expect(Repo, :get, fn Account, 123 -> %Account{id: 123, runner_log_retention_days: 14} end)
    before_cutoff = DateTime.add(DateTime.utc_now(), -14, :day)

    expect(IngestRepo, :query!, 2, fn sql, %{"account_id" => 123, "cutoff" => cutoff} ->
      assert sql =~ "account_id = {account_id:Int64} AND inserted_at < {cutoff:DateTime64(6)}"
      assert DateTime.compare(cutoff, before_cutoff) in [:gt, :eq]
      assert DateTime.diff(cutoff, before_cutoff) < 5
      send(self(), {:mutation, sql})
      %{rows: []}
    end)

    expect(Oban, :insert!, fn changeset ->
      assert Ecto.Changeset.get_field(changeset, :worker) == Oban.Worker.to_string(PruneArchivedLogsWorker)
      assert Ecto.Changeset.get_field(changeset, :args) == %{"account_id" => 123}
      %Oban.Job{}
    end)

    assert :ok = PruneRetentionOverridesWorker.perform(%Oban.Job{args: %{"account_id" => 123}})
    assert_received {:mutation, "ALTER TABLE runner_job_logs " <> _}
    assert_received {:mutation, "ALTER TABLE runner_job_machine_metrics " <> _}
  end

  test "queued work reloads the current policy instead of trusting serialized days" do
    expect(Repo, :get, fn Account, 123 -> %Account{id: 123} end)
    reject(&IngestRepo.query!/2)
    reject(&Oban.insert!/1)

    assert :ok = PruneRetentionOverridesWorker.perform(%Oban.Job{args: %{"account_id" => 123, "retention_days" => 7}})
  end

  test "deleted accounts are ignored" do
    expect(Repo, :get, fn Account, 123 -> nil end)
    reject(&IngestRepo.query!/2)
    assert :ok = PruneRetentionOverridesWorker.perform(%Oban.Job{args: %{"account_id" => 123}})
  end

  test "scheduler enqueues a bounded account page and a keyset continuation" do
    expect(Repo, :all, fn query ->
      assert query.limit.expr == 100
      assert inspect(query) =~ "not is_nil"
      assert inspect(query) =~ "a0.id > ^100"
      Enum.to_list(101..200)
    end)

    expect(Oban, :insert!, 101, fn changeset ->
      send(self(), {:queued, Ecto.Changeset.get_field(changeset, :args)})
      %Oban.Job{}
    end)

    assert :ok = PruneRetentionOverridesWorker.perform(%Oban.Job{args: %{"after_account_id" => 100}})
    assert_received {:queued, %{"account_id" => 101}}
    assert_received {:queued, %{"account_id" => 200}}
    assert_received {:queued, %{"after_account_id" => 200}}
  end

  test "an empty scheduler page does not enqueue more work" do
    expect(Repo, :all, fn _query -> [] end)
    reject(&Oban.insert!/1)
    assert :ok = PruneRetentionOverridesWorker.perform(%Oban.Job{args: %{}})
  end
end
