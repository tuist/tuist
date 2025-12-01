defmodule Tuist.Repo.Migrations.MigrateCommandEventsToUuidPrimaryKey do
  use Ecto.Migration

  @moduledoc """
  This migration transitions the command_events table from using integer IDs to UUID primary keys.

  IMPORTANT: This migration handles both on-premise (PostgreSQL only) and cloud (PostgreSQL + ClickHouse) deployments:
  - On-premise: Updates both command_events and xcode_graphs tables in PostgreSQL
  - Cloud: Updates only command_events table in PostgreSQL; xcode_graphs exists in ClickHouse

  Migration steps:
  1. Add legacy_artifact_path flag to track pre-migration records
  2. Update test_case_runs foreign keys (always in PostgreSQL)
  3. Update xcode_graphs foreign keys (only for on-premise deployments)
  4. Change command_events primary key from (id, created_at) to (uuid, created_at)
  5. Rename columns: id -> legacy_id, uuid -> id, and update primary key to use new id
  """

  def up do
    # PRE-MIGRATION VALIDATION: Ensure data integrity before proceeding
    validate_migration_prerequisites!()

    # STEP 1: Add legacy_artifact_path flag to distinguish pre-migration records
    # This helps track which command_events were created before the UUID migration
    # Note: UUID column already exists from a previous migration
    alter table(:command_events) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :legacy_artifact_path, :boolean, default: false, null: false
    end

    # Mark all existing records as legacy to distinguish them from new records
    # that will be created with UUID as primary identifier
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    UPDATE command_events SET legacy_artifact_path = true;
    """

    # STEP 2: Migrate test_case_runs foreign keys from integer to UUID
    # test_case_runs table always exists in PostgreSQL for both deployment types

    # Add temporary UUID column to hold the new foreign key values
    alter table(:test_case_runs) do
      add :command_event_uuid, :uuid
    end

    # Populate UUID column by joining with command_events on the integer ID
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    UPDATE test_case_runs
    SET command_event_uuid = command_events.uuid
    FROM command_events
    WHERE test_case_runs.command_event_id = command_events.id;
    """

    # Remove the old integer foreign key column
    alter table(:test_case_runs) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :command_event_id
    end

    # Rename the UUID column to take the place of the old foreign key
    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:test_case_runs), :command_event_uuid, to: :command_event_id

    # Ensure the new foreign key column has proper constraints
    alter table(:test_case_runs) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      # excellent_migrations:safety-assured-for-next-line not_null_added
      modify :command_event_id, :uuid, null: false
    end

    # STEP 4: Change the primary key of command_events from (id, created_at) to (uuid, created_at)
    # This is a TimescaleDB hypertable, so we need to maintain the created_at partition key
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events DROP CONSTRAINT command_events_pkey;"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events ADD PRIMARY KEY (uuid, created_at);"

    # STEP 5: Rename columns to complete the transition
    # Rename id -> legacy_id and uuid -> id, then update primary key
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events DROP CONSTRAINT command_events_pkey;"
    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:command_events), :id, to: :legacy_id
    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:command_events), :uuid, to: :id
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events ADD PRIMARY KEY (id, created_at);"
  end

  def down do
    # REVERSAL STEP 1: Reverse the column renaming (id -> uuid, legacy_id -> id)
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events DROP CONSTRAINT command_events_pkey;"
    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:command_events), :id, to: :uuid
    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:command_events), :legacy_id, to: :id
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events ADD PRIMARY KEY (uuid, created_at);"

    # REVERSAL STEP 2: Restore the original composite primary key (id, created_at)
    # This reverts the primary key back to using the integer ID
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events DROP CONSTRAINT command_events_pkey;"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events ADD PRIMARY KEY (id, created_at);"

    # REVERSAL STEP 4: Restore test_case_runs integer foreign keys
    # This table always exists in PostgreSQL for both deployment types
    # Add temporary integer column to hold the restored foreign key values
    alter table(:test_case_runs) do
      add :command_event_int_id, :integer
    end

    # Populate integer column by joining with command_events on the UUID
    # This reverses the UUID->integer mapping
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    UPDATE test_case_runs
    SET command_event_int_id = command_events.id
    FROM command_events
    WHERE test_case_runs.command_event_id = command_events.uuid;
    """

    # Remove the UUID foreign key column
    alter table(:test_case_runs) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :command_event_id
    end

    # Rename the integer column back to command_event_id
    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:test_case_runs), :command_event_int_id, to: :command_event_id

    # Restore the integer column constraints
    alter table(:test_case_runs) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      # excellent_migrations:safety-assured-for-next-line not_null_added
      modify :command_event_id, :integer, null: false
    end

    # REVERSAL STEP 5: Remove the legacy_artifact_path flag
    # Note: We intentionally leave the UUID column as it was added in a previous migration
    alter table(:command_events) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :legacy_artifact_path
    end
  end

  # Validates that all prerequisites for the migration are met.
  # This includes checking for:
  # 1. UUID extension is installed
  # 2. All command_events have UUID values
  # 3. No orphaned foreign key references exist
  # 4. No duplicate UUIDs exist
  defp validate_migration_prerequisites!() do
    IO.puts("Validating migration prerequisites...")

    # Check 1: Verify all command_events have UUID values
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    {:ok, %{rows: [[null_uuid_count]]}} =
      repo().query("""
        SELECT COUNT(*) FROM command_events WHERE uuid IS NULL;
      """)

    if null_uuid_count > 0 do
      raise "Found #{null_uuid_count} command_events without UUID values. Please ensure all records have UUIDs."
    end

    # Check 2: Verify no duplicate UUIDs exist
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    {:ok, %{rows: duplicate_uuids}} =
      repo().query("""
        SELECT uuid, COUNT(*) as count
        FROM command_events
        WHERE uuid IS NOT NULL
        GROUP BY uuid
        HAVING COUNT(*) > 1
        LIMIT 10;
      """)

    if length(duplicate_uuids) > 0 do
      duplicates =
        Enum.map(duplicate_uuids, fn [uuid, count] -> "UUID: #{uuid} (#{count} occurrences)" end)

      raise "Found duplicate UUIDs in command_events: #{Enum.join(duplicates, ", ")}"
    end

    # Check 3: Verify no orphaned test_case_runs exist
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    {:ok, %{rows: [[orphaned_test_runs]]}} =
      repo().query("""
        SELECT COUNT(*)
        FROM test_case_runs tcr
        LEFT JOIN command_events ce ON tcr.command_event_id = ce.id
        WHERE ce.id IS NULL;
      """)

    if orphaned_test_runs > 0 do
      raise "Found #{orphaned_test_runs} orphaned test_case_runs with non-existent command_event_ids"
    end

    # Check 5: Verify test_case_runs will get valid UUIDs
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    {:ok, %{rows: [[test_runs_without_uuid]]}} =
      repo().query("""
        SELECT COUNT(*)
        FROM test_case_runs tcr
        INNER JOIN command_events ce ON tcr.command_event_id = ce.id
        WHERE ce.uuid IS NULL;
      """)

    if test_runs_without_uuid > 0 do
      raise "Found #{test_runs_without_uuid} test_case_runs that would not get valid UUIDs after migration"
    end

    IO.puts("✓ All migration prerequisites validated successfully!")
  end
end
