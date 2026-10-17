defmodule Tuist.Runners.Workers.PruneRetentionOverridesIntegrationTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.JobLog
  alias Tuist.Runners.JobMachineMetric
  alias Tuist.Runners.Workers.PruneRetentionOverridesWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "real mutations preserve recent data and other accounts in both runner tables" do
    account = AccountsFixtures.account_fixture()
    other = AccountsFixtures.account_fixture()
    {:ok, _} = Accounts.update_account_retention(account, %{runner_log_retention_days: 14})
    now = DateTime.utc_now()

    for {schema, extra} <- [{JobLog, %{line_number: 1, ts: now, message: "log"}}, {JobMachineMetric, %{timestamp: 1.0}}] do
      rows =
        for {id, owner, age} <- [{9_700_001, account.id, 21}, {9_700_002, account.id, 7}, {9_700_003, other.id, 21}] do
          Map.merge(extra, %{workflow_job_id: id, account_id: owner, inserted_at: DateTime.add(now, -age, :day)})
        end

      IngestRepo.insert_all(schema, rows)
    end

    # Await the production mutations in this test so assertions do not race
    # ClickHouse's background mutation executor.
    expect(IngestRepo, :query!, 2, fn sql, params ->
      Mimic.call_original(IngestRepo, :query!, [String.replace(sql, "mutations_sync = 0", "mutations_sync = 1"), params])
    end)

    assert :ok = perform_job(PruneRetentionOverridesWorker, %{"account_id" => account.id})

    for schema <- [JobLog, JobMachineMetric] do
      assert ClickHouseRepo.all(from(row in schema, order_by: row.workflow_job_id, select: row.workflow_job_id)) ==
               [9_700_002, 9_700_003]
    end
  end
end
