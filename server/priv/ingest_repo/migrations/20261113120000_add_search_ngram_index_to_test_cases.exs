defmodule Tuist.IngestRepo.Migrations.AddSearchNgramIndexToTestCases do
  @moduledoc """
  Adds a case-insensitive n-gram skip index for dashboard search on `test_cases`.

  `test_cases` is `ORDER BY (project_id, module_name, suite_name, name, id)`,
  so a name search within a project reads every granule of the project. The
  existing `idx_*_ngram` indexes cover the raw columns, which only a
  case-sensitive `LIKE` can use; `ILIKE` and `positionCaseInsensitive` never
  prune with them. Dashboard search matches case-insensitively across module,
  suite and name, so it filters on
  `lowerUTF8(concat(module_name, ' ', suite_name, ' ', name)) LIKE '%term%'`,
  which this index covers with the expression written exactly the same way.
  A selective term then reads a few granules instead of the whole project, so
  large projects stay under the search's read limits.

  `ADD INDEX` is metadata-only and covers new parts. Existing parts are
  indexed by one asynchronous `MATERIALIZE INDEX` mutation per partition
  (`IndexMaterialization.materialize_index_statements/4`), and the deploy does
  not wait for them. Parts not yet materialized are still read correctly, only
  without skipping.
  """
  use Ecto.Migration

  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_cases
    ADD INDEX IF NOT EXISTS idx_search_ngram lowerUTF8(concat(module_name, ' ', suite_name, ' ', name))
    TYPE ngrambf_v1(3, 65536, 3, 0) GRANULARITY 4
    """

    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    IngestRepo
    |> IndexMaterialization.partition_ids(database, "test_cases")
    |> then(
      &IndexMaterialization.materialize_index_statements(
        database,
        "test_cases",
        "idx_search_ngram",
        &1
      )
    )
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    |> Enum.each(&execute/1)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_cases DROP INDEX IF EXISTS idx_search_ngram"
  end
end
