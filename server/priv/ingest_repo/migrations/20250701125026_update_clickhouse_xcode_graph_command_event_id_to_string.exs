defmodule Tuist.ClickHouseRepo.Migrations.UpdateClickhouseXcodeGraphCommandEventIdToString do
  use Ecto.Migration

  @moduledoc """
  This migration updates the xcode_graphs table in ClickHouse to use UUID foreign keys
  instead of integer IDs, matching the PostgreSQL migration for command_events.

  IMPORTANT: This migration is ONLY for cloud deployments where xcode_graphs exists in ClickHouse.
  On-premise deployments store xcode_graphs in PostgreSQL and are handled by migration 20250625090000.

  PREREQUISITES:
  - The PostgreSQL migration (20250625090000) MUST run first to ensure UUIDs exist in command_events
  - This migration performs a cross-database join between ClickHouse and PostgreSQL

  APPROACH:
  - ClickHouse doesn't support ALTER COLUMN for type changes, so we recreate the table
  - We use ClickHouse's postgresql() table function to join with PostgreSQL data
  - The migration preserves all existing data by mapping integer IDs to UUIDs

  FAILURE MODES:
  - If PostgreSQL connection fails, the migration will fail
  - If any command_event_id in ClickHouse doesn't exist in PostgreSQL, that row will be lost
  """

  def up do
    secrets = Tuist.Environment.decrypt_secrets()
    skip_data_migration? = System.get_env("TUIST_SKIP_DATA_MIGRATION") in ["true", "1"]

    # PRE-MIGRATION VALIDATION: Ensure data integrity before proceeding
    unless skip_data_migration? do
      validate_clickhouse_migration_prerequisites!(secrets)
    end

    # Create the new table structure with command_event_id as UUID type
    # All other columns remain the same
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE xcode_graphs_new (
      id String,
      name String,
      command_event_id UUID,
      binary_build_duration Nullable(UInt32),
      inserted_at DateTime
    ) ENGINE = MergeTree()
    ORDER BY (id, inserted_at)
    """)

    # STEP 2: Extract PostgreSQL connection details from Mix config
    # This ensures we use the correct database in all environments (dev, test, prod)
    # In production, DATABASE_URL overrides the config values
    unless skip_data_migration? do
      repo_config = Application.get_env(:tuist, Tuist.Repo, [])

      # Try DATABASE_URL first (for production), then fall back to Mix config
      {username, password, host, port, database} =
        if database_url = Tuist.Environment.ipv4_database_url(secrets) do
          uri = URI.parse(database_url)
          [user, pass] = String.split(uri.userinfo || "postgres:postgres", ":")
          db_host = uri.host || "localhost"
          db_port = uri.port || 5432
          db_name = String.trim_leading(uri.path || "/tuist", "/")
          {user, pass, db_host, db_port, db_name}
        else
          # Use Mix config values (for dev/test environments)
          # Handle test partition suffix for parallel test execution
          db_name =
            case Keyword.get(repo_config, :database) do
              "tuist_test" <> _ = test_db -> test_db <> System.get_env("MIX_TEST_PARTITION", "")
              other -> other || "tuist_development"
            end

          {
            Keyword.get(repo_config, :username),
            Keyword.get(repo_config, :password),
            Keyword.get(repo_config, :hostname, "localhost"),
            Keyword.get(repo_config, :port, 5432),
            db_name
          }
        end

      # STEP 3: Migrate data with cross-database join
      # This query:
      # 1. Reads all rows from the existing xcode_graphs table in ClickHouse
      # 2. Joins with command_events table in PostgreSQL to get the UUID for each integer ID
      # 3. Inserts the data into the new table with UUIDs instead of integer IDs
      #
      # Note: After the PostgreSQL migration, 'id' is now the UUID and 'legacy_id' is the old integer
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      INSERT INTO xcode_graphs_new
      SELECT
        xg.id,
        xg.name,
        ce.id as command_event_id,
        xg.binary_build_duration,
        xg.inserted_at
      FROM xcode_graphs xg
      JOIN postgresql('#{host}:#{port}', '#{database}', 'command_events', '#{username}', '#{password}', 'public') ce
      ON toInt64(xg.command_event_id) = ce.legacy_id
      """)
    end

    # STEP 4: Atomic table swap
    # Drop the old table and rename the new one to take its place
    # This is atomic within ClickHouse, minimizing downtime
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE xcode_graphs")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE xcode_graphs_new TO xcode_graphs")
  end

  def down do
    secrets = Tuist.Environment.decrypt_secrets()
    skip_data_migration? = System.get_env("TUIST_SKIP_DATA_MIGRATION") in ["true", "1"]

    # REVERSAL: Restore the original table structure with integer foreign keys
    # This follows the same pattern as the up migration but in reverse

    # STEP 1: Create a table with the original integer column type
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS xcode_graphs_old")

    # Create table with command_event_id as UInt64 (original type)
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE xcode_graphs_old (
      id String,
      name String,
      command_event_id UInt64,
      binary_build_duration Nullable(UInt32),
      inserted_at DateTime
    ) ENGINE = MergeTree()
    ORDER BY (id, inserted_at)
    """)

    # STEP 2: Extract PostgreSQL connection details (same as up migration)
    unless skip_data_migration? do
      repo_config = Application.get_env(:tuist, Tuist.Repo, [])

      # Try DATABASE_URL first (for production), then fall back to Mix config
      {username, password, host, port, database} =
        if database_url = Tuist.Environment.ipv4_database_url(secrets) do
          uri = URI.parse(database_url)
          [user, pass] = String.split(uri.userinfo || "postgres:postgres", ":")
          db_host = uri.host || "localhost"
          db_port = uri.port || 5432
          db_name = String.trim_leading(uri.path || "/tuist", "/")
          {user, pass, db_host, db_port, db_name}
        else
          # Use Mix config values (for dev/test environments)
          # Handle test partition suffix for parallel test execution
          db_name =
            case Keyword.get(repo_config, :database) do
              "tuist_test" <> _ = test_db -> test_db <> System.get_env("MIX_TEST_PARTITION", "")
              other -> other || "tuist_development"
            end

          {
            Keyword.get(repo_config, :username, "postgres"),
            Keyword.get(repo_config, :password, "postgres"),
            Keyword.get(repo_config, :hostname, "localhost"),
            Keyword.get(repo_config, :port, 5432),
            db_name
          }
        end

      # STEP 3: Migrate data back with reverse mapping (UUID -> integer)
      # This query:
      # 1. Reads all rows from the current xcode_graphs table with UUID foreign keys
      # 2. Joins with command_events in PostgreSQL to get the integer ID for each UUID
      # 3. Inserts the data with integer IDs restored
      #
      # Note: After the PostgreSQL migration, 'id' is now the UUID and 'legacy_id' is the old integer
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      INSERT INTO xcode_graphs_old
      SELECT
        xg.id,
        xg.name,
        ce.legacy_id as command_event_id,
        xg.binary_build_duration,
        xg.inserted_at
      FROM xcode_graphs xg
      JOIN postgresql('#{host}:#{port}', '#{database}', 'command_events', '#{username}', '#{password}', 'public') ce
      ON xg.command_event_id = ce.id
      """)
    end

    # STEP 4: Atomic table swap to complete the rollback
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE xcode_graphs")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE xcode_graphs_old TO xcode_graphs")
  end

  # Validates that all prerequisites for the ClickHouse migration are met.
  # This includes checking for:
  # 1. PostgreSQL migration has been completed
  # 2. All command_event_ids in ClickHouse exist in PostgreSQL
  # 3. PostgreSQL connection is working
  defp validate_clickhouse_migration_prerequisites!(secrets) do
    IO.puts("Validating ClickHouse migration prerequisites...")

    # Extract PostgreSQL connection details
    repo_config = Application.get_env(:tuist, Tuist.Repo, [])

    {username, password, host, port, database} =
      if database_url = Tuist.Environment.ipv4_database_url(secrets) do
        uri = URI.parse(database_url)
        [user, pass] = String.split(uri.userinfo || "postgres:postgres", ":")
        db_host = uri.host || "localhost"
        db_port = uri.port || 5432
        db_name = String.trim_leading(uri.path || "/tuist", "/")
        {user, pass, db_host, db_port, db_name}
      else
        db_name =
          case Keyword.get(repo_config, :database) do
            "tuist_test" <> _ = test_db -> test_db <> System.get_env("MIX_TEST_PARTITION", "")
            other -> other || "tuist_development"
          end

        {
          Keyword.get(repo_config, :username),
          Keyword.get(repo_config, :password),
          Keyword.get(repo_config, :hostname, "localhost"),
          Keyword.get(repo_config, :port, 5432),
          db_name
        }
      end

    # Check 1: Verify PostgreSQL connection is working by testing a simple query
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    try do
      {:ok, %{rows: [[count]]}} =
        repo().query("""
          SELECT count(*)
          FROM postgresql('#{host}:#{port}', '#{database}', 'command_events', '#{username}', '#{password}')
          LIMIT 1
        """)

      IO.puts("✓ PostgreSQL connection verified: found #{count} command_events")
    rescue
      e ->
        raise "Failed to connect to PostgreSQL database. Error: #{inspect(e)}"
    end

    # Check 2: Verify all command_events have UUIDs in PostgreSQL
    # Note: After the PostgreSQL migration, 'id' is now the UUID field
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    {:ok, %{rows: [[null_uuid_count]]}} =
      repo().query("""
        SELECT count(*)
        FROM postgresql('#{host}:#{port}', '#{database}', 'command_events', '#{username}', '#{password}')
        WHERE id IS NULL
      """)

    if null_uuid_count > 0 do
      raise "Found #{null_uuid_count} command_events in PostgreSQL without UUID values. Please ensure PostgreSQL migration completed successfully."
    end

    IO.puts("✓ All command_events have UUID values")

    # Check 3: Count total rows in ClickHouse xcode_graphs
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    {:ok, %{rows: [[total_ch_rows]]}} =
      repo().query("""
        SELECT COUNT(*) FROM xcode_graphs
      """)

    IO.puts("Found #{total_ch_rows} rows in ClickHouse xcode_graphs table")

    if total_ch_rows > 0 do
      # Check 4: Verify all command_event_ids in ClickHouse exist in PostgreSQL
      # Note: After the PostgreSQL migration, 'legacy_id' is now the old integer field
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      {:ok, %{rows: [[orphaned_count]]}} =
        repo().query("""
          SELECT COUNT(*)
          FROM xcode_graphs xg
          LEFT JOIN postgresql('#{host}:#{port}', '#{database}', 'command_events', '#{username}', '#{password}', 'public') ce
          ON toInt64(xg.command_event_id) = ce.legacy_id
          WHERE ce.legacy_id IS NULL
        """)

      if orphaned_count > 0 do
        # Get sample of orphaned IDs for debugging
        # Note: After the PostgreSQL migration, 'legacy_id' is now the old integer field
        # excellent_migrations:safety-assured-for-next-line raw_sql_executed
        {:ok, %{rows: orphaned_samples}} =
          repo().query("""
            SELECT xg.command_event_id
            FROM xcode_graphs xg
            LEFT JOIN postgresql('#{host}:#{port}', '#{database}', 'command_events', '#{username}', '#{password}', 'public') ce
            ON toInt64(xg.command_event_id) = ce.legacy_id
            WHERE ce.legacy_id IS NULL
            LIMIT 10
          """)

        sample_ids = Enum.map_join(orphaned_samples, ", ", fn [id] -> id end)

        raise "Found #{orphaned_count} xcode_graphs rows with command_event_ids that don't exist in PostgreSQL. Sample IDs: #{sample_ids}. These rows would be lost during migration!"
      end

      # Check 5: Verify we can successfully map at least one ID
      # Note: After the PostgreSQL migration, 'id' is now the UUID and 'legacy_id' is the old integer
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      {:ok, %{rows: test_mapping}} =
        repo().query("""
          SELECT xg.command_event_id, ce.id
          FROM xcode_graphs xg
          JOIN postgresql('#{host}:#{port}', '#{database}', 'command_events', '#{username}', '#{password}', 'public') ce
          ON toInt64(xg.command_event_id) = ce.legacy_id
          LIMIT 1
        """)

      if length(test_mapping) == 0 do
        raise "Unable to map any command_event_ids to UUIDs. This suggests a data integrity issue."
      else
        [[sample_id, sample_uuid]] = test_mapping

        uuid_string =
          case sample_uuid do
            <<_::binary>> -> Base.encode16(sample_uuid, case: :lower)
            other -> inspect(other)
          end

        IO.puts("✓ Successfully tested ID mapping: #{sample_id} -> #{uuid_string}")
      end
    end

    IO.puts("✓ All ClickHouse migration prerequisites validated successfully!")
  end
end
