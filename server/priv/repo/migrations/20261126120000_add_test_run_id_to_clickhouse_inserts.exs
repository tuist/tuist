defmodule Tuist.Repo.Migrations.AddTestRunIdToClickhouseInserts do
  @moduledoc """
  Lets a command event's inserts wait, under its test run and no commit, for
  the run's report to declare them to the commit's fold
  (`Tuist.Tests.Coverage.RunInputs`): a shard or processed report can declare
  the run after its command event landed.
  """
  use Ecto.Migration

  def change do
    alter table(:clickhouse_inserts) do
      add :test_run_id, :uuid
    end

    # The table only holds a day of inserts, so the index builds in moments.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:clickhouse_inserts, [:project_id, :test_run_id],
             where: "test_run_id IS NOT NULL AND git_commit_sha IS NULL"
           )
  end
end
