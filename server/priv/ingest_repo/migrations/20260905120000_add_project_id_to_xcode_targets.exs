defmodule Tuist.IngestRepo.Migrations.AddProjectIdToXcodeTargets do
  @moduledoc """
  Denormalizes `project_id` onto `xcode_targets` and adds a project-ordered
  projection.

  `xcode_targets` carries every project's rows and is ordered by
  `(inserted_at, id)`. The module cache analytics reach a project only through
  a join on `command_events`, which gives the scan nothing to prune with: at the
  dashboard's 30-day default a single query read ~960M rows and ~30 GiB in
  production and took ~18s, and the Modules page runs five of them at once.
  With `project_id` on the row and a projection ordered by
  `(project_id, inserted_at)`, the same queries become a range over one
  project's rows.

  Backfilled in place with a dictionary lookup over `command_events`, the same
  shape as `20260609120000_denormalize_project_id_on_cas_outputs`, and
  serialized across pods with a Postgres advisory lock the way
  `20260721115000_add_project_id_to_test_case_events` is: ClickHouse migrations
  run without a migration lock, and one pod dropping the dictionary while
  another is mid-mutation would crash that pod on boot.

  The backfill mutation rewrites roughly a billion rows and runs synchronously,
  so this migration is expected to take a long time.
  """
  use Ecto.Migration

  alias Tuist.ClickHouseDictionarySource
  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @dict_name "command_event_project_ids_for_xcode_targets"
  # command_events holds ~34M rows but only events that reported targets can
  # have xcode_targets rows, which is about a sixth of them, so the dictionary
  # is built from those alone.
  @dict_source_query "SELECT id, project_id FROM command_events WHERE cacheable_targets_count > 0 OR test_targets_count > 0"
  @projection_name "proj_by_project_inserted_at"
  @lock_id 20_260_905_120_000

  def up do
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

            add_project_ordered_projection()
            materialize_project_ordered_projection()
          end,
          timeout: :infinity
        )
      end)
  end

  def down do
    IngestRepo.query!("ALTER TABLE xcode_targets DROP PROJECTION IF EXISTS #{@projection_name}")
    IngestRepo.query!("ALTER TABLE xcode_targets DROP COLUMN IF EXISTS project_id")
  end

  defp add_project_id_column do
    IngestRepo.query!("""
    ALTER TABLE xcode_targets
    ADD COLUMN IF NOT EXISTS project_id Int64 DEFAULT 0 AFTER command_event_id
    """)
  end

  defp create_project_ids_dictionary do
    IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")

    IngestRepo.query!(
      """
      CREATE DICTIONARY #{@dict_name} (
        id UUID,
        project_id Int64
      )
      PRIMARY KEY id
      SOURCE(#{ClickHouseDictionarySource.local_query(IngestRepo, @dict_source_query)})
      LAYOUT(HASHED())
      LIFETIME(0)
      """,
      [],
      ClickHouseDictionarySource.query_opts()
    )
  end

  defp backfill_project_id do
    Logger.info("Starting xcode_targets project_id backfill mutation")

    IngestRepo.query!(
      """
      ALTER TABLE xcode_targets
      UPDATE project_id = dictGetOrDefault('#{@dict_name}', 'project_id', command_event_id, toInt64(0))
      WHERE project_id = 0
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished xcode_targets project_id backfill mutation")
  end

  # Only the columns the module cache analytics read, so the projection stays a
  # fraction of the base table. A query that touches any other column falls back
  # to the base table.
  defp add_project_ordered_projection do
    IngestRepo.query!("""
    ALTER TABLE xcode_targets
    ADD PROJECTION IF NOT EXISTS #{@projection_name}
    (
      SELECT
        project_id,
        inserted_at,
        command_event_id,
        name,
        product,
        binary_cache_hash,
        binary_cache_hit,
        sources_hash,
        resources_hash,
        copy_files_hash,
        core_data_models_hash,
        target_scripts_hash,
        environment_hash,
        headers_hash,
        deployment_target_hash,
        info_plist_hash,
        entitlements_hash,
        dependencies_hash,
        project_settings_hash,
        target_settings_hash,
        buildable_folders_hash,
        additional_hashing_inputs_hash,
        external_hash,
        dependencies
      ORDER BY (project_id, inserted_at)
    )
    """)
  end

  defp materialize_project_ordered_projection do
    Logger.info("Starting xcode_targets project-ordered projection materialization")

    IngestRepo.query!(
      """
      ALTER TABLE xcode_targets
      MATERIALIZE PROJECTION #{@projection_name}
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished xcode_targets project-ordered projection materialization")
  end
end
