defmodule Tuist.IngestRepo.Migrations.AddProjectIdToTestCaseEvents do
  @moduledoc """
  Denormalizes `project_id` onto `test_case_events`.

  The materialized view that maintains `test_case_states` reads from this table
  and has to write a `project_id`, because every read of the projection is
  project-scoped so it can ride the `(project_id, test_case_id)` sort prefix. A
  materialized view sees only the rows of the insert that triggered it and
  cannot join back to `test_cases` for the answer, so the column has to be on
  the event row itself.

  Backfilled in place with a dictionary lookup, the same shape as
  `20260609120000_denormalize_project_id_on_cas_outputs`. The table is small
  (~1.6M rows, ~60 MiB), so this is a cheap mutation rather than a shadow-table
  swap.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @dict_name "test_case_project_ids_for_events"
  @lock_id 20_260_721_115_000

  def up do
    # ClickHouse migrations run without a migration lock (`ecto_ch` doesn't
    # implement the contract), so every pod runs this on startup. Unlike the
    # cas_outputs precedent this one creates *and drops* a dictionary, and a pod
    # dropping it while another is mid-mutation would fail that pod's migration
    # and crash it on boot. Postgres is shared across pods, so we borrow an
    # advisory lock to serialize, the same way
    # `20260425120000_rename_legacy_quarantine_events` does.
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo ->
        Repo.transaction(
          fn ->
            Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_id])

            add_project_id_column()

            try do
              create_project_ids_dictionary()
              backfill_project_id()
            after
              IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")
            end
          end,
          timeout: :infinity
        )
      end)
  end

  def down do
    IngestRepo.query!("ALTER TABLE test_case_events DROP COLUMN IF EXISTS project_id")
  end

  defp add_project_id_column do
    IngestRepo.query!("""
    ALTER TABLE test_case_events
    ADD COLUMN IF NOT EXISTS project_id Int64 DEFAULT 0 AFTER test_case_id
    """)
  end

  defp create_project_ids_dictionary do
    IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")

    # `test_cases` is a ReplacingMergeTree, so the source can hold several rows
    # per id. `project_id` never changes for a test case, so whichever row the
    # dictionary keeps carries the same answer.
    IngestRepo.query!("""
    CREATE DICTIONARY #{@dict_name} (
      id UUID,
      project_id Int64
    )
    PRIMARY KEY id
    SOURCE(CLICKHOUSE(TABLE 'test_cases'))
    LAYOUT(HASHED())
    LIFETIME(0)
    """)
  end

  defp backfill_project_id do
    Logger.info("Starting test_case_events project_id backfill mutation")

    IngestRepo.query!(
      """
      ALTER TABLE test_case_events
      UPDATE project_id = dictGetOrDefault('#{@dict_name}', 'project_id', test_case_id, toInt64(0))
      WHERE project_id = 0
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished test_case_events project_id backfill mutation")
  end
end
