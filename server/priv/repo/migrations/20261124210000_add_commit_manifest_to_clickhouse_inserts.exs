defmodule Tuist.Repo.Migrations.AddCommitManifestToClickhouseInserts do
  @moduledoc """
  Lets a commit's fold find, in PostgreSQL, every ClickHouse insert of its
  runs it reads (`Tuist.Tests.Coverage.RunInputs`): the commit they belong
  to (`git_commit_sha`), and how many rows each wrote (`row_count`), for
  inserts whose rows don't share one `inserted_at`. A null `row_count`
  declares rows the writer is still writing.
  """
  use Ecto.Migration

  def change do
    alter table(:clickhouse_inserts) do
      add :git_commit_sha, :string
      add :row_count, :bigint
    end

    # The table only holds a day of inserts, so the index builds in moments.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:clickhouse_inserts, [:project_id, :git_commit_sha],
             where: "git_commit_sha IS NOT NULL"
           )
  end
end
