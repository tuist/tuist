defmodule Tuist.ClickHouse.SchemaClone do
  @moduledoc """
  Clones a ClickHouse schema from one server to another, rewriting the engine
  family so the destination's tables are replicated.

  This is how the in-cluster ClickHouse gets its schema during the migration
  off ClickHouse Cloud (spec #73), and it exists because replaying the ingest
  migrations against the destination cannot produce the right engines.

  The ingest migrations emit DDL two ways: `IngestRepo.query!/1` with a SQL
  string, and `Ecto.Migration.execute/1` with a SQL string. The second does
  not pass through the repository at all. It reaches
  `Ecto.Adapters.SQL.execute_ddl/4`, which calls the adapter's own `query!`
  with the connection metadata rather than the repo module, so no override on
  `Tuist.IngestRepo` can see it. Intercepting both would mean wrapping the
  adapter or editing the migrations, and neither is worth doing when the
  destination's schema can be taken from the source it has to match anyway.

  So the schema is cloned from the source's own `system.tables`, which is also
  the only definition guaranteed to match what production actually runs rather
  than what the migration history says it should. The migration version table
  is copied last, so `Ecto.Migrator` on the destination sees a database that is
  already current and future migrations apply normally on top.

  ## The rewrite

  ClickHouse Cloud reports its tables as the `Shared*` engine family, which
  does not exist outside Cloud, and it already carries the Keeper path
  arguments a self-managed replicated engine takes:

      ENGINE = SharedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', updated_at)

  Mapping `Shared` to `Replicated` is therefore the whole transformation, and
  the path arguments are left in place: they are the same macros this server
  would choose by default, and the destination is configured with
  `database_replicated_allow_replicated_engine_arguments = 2`, which accepts
  them and substitutes its own defaults. A source that is already self-managed
  reports `Replicated*` or plain `MergeTree`, and both are handled.

  ## What is deliberately not cloned

  Materialized views whose storage is implicit own an inner table named
  `.inner_id.<uuid>`. Those are skipped: recreating the view recreates its
  inner table, and cloning the source's would tie the destination to a UUID
  the view no longer has. Data for those targets is rebuilt from the base
  tables afterwards rather than copied.
  """

  alias Tuist.ClickHouse.Endpoints

  require Logger

  @engine_families ~w(MergeTree ReplacingMergeTree AggregatingMergeTree SummingMergeTree CollapsingMergeTree VersionedCollapsingMergeTree GraphiteMergeTree)

  @doc """
  Clones the source repository's schema into the destination's database.

  Idempotent: every statement is emitted with `IF NOT EXISTS`, so a partial
  run is completed by running it again.
  """
  def run(opts \\ []) do
    Endpoints.with_repos(opts, fn source, target ->
      objects = read_objects(source)

      Logger.info(
        "Cloning #{length(objects.tables)} table(s) and #{length(objects.views)} view(s) from #{source.database} into #{target.database}"
      )

      tables = Enum.map(objects.tables, &clone_object(source, target, &1))
      views = Enum.map(objects.views, &clone_object(source, target, &1))

      report = %{
        tables: summarize(tables),
        views: summarize(views),
        migrations_copied: copy_schema_migrations(source, sync_replica(target)),
        skipped_inner_tables: length(objects.skipped_inner)
      }

      Logger.info("Schema clone finished: #{inspect(report)}")
      {:ok, report}
    end)
  end

  @doc """
  Rewrites a source `CREATE` statement for the destination.

  Public so the rewrite is testable without a ClickHouse to talk to, which is
  the part worth testing: the engine mapping and the database requalification.
  """
  def rewrite(ddl, source_database, target_database) do
    ddl
    |> rewrite_engine()
    |> requalify_database(source_database, target_database)
    |> add_if_not_exists()
  end

  defp rewrite_engine(ddl) do
    Enum.reduce(@engine_families, ddl, fn family, acc ->
      String.replace(acc, "ENGINE = Shared#{family}", "ENGINE = Replicated#{family}")
    end)
  end

  defp requalify_database(ddl, database, database), do: ddl

  # Only where a database qualifier can legally appear, rather than everywhere
  # the name occurs. The name is not guaranteed to be distinctive: staging's
  # source database is literally called `database`, so replacing every
  # occurrence of `database.` would rewrite `system.database_roles`, a column
  # called `database_id`, and the contents of a string literal in a DEFAULT
  # expression. Matching the keyword that introduces the qualifier is what
  # keeps the rewrite to object names.
  defp requalify_database(ddl, source_database, target_database) do
    escaped = Regex.escape(source_database)

    Regex.replace(
      ~r/\b(TABLE|VIEW|DICTIONARY|TO|FROM|JOIN|INTO)(\s+)`?#{escaped}`?\./i,
      ddl,
      fn _match, keyword, whitespace -> "#{keyword}#{whitespace}#{target_database}." end
    )
  end

  defp add_if_not_exists(ddl) do
    ddl
    |> String.replace(~r/\ACREATE TABLE (?!IF NOT EXISTS)/, "CREATE TABLE IF NOT EXISTS ")
    |> String.replace(~r/\ACREATE MATERIALIZED VIEW (?!IF NOT EXISTS)/, "CREATE MATERIALIZED VIEW IF NOT EXISTS ")
    |> String.replace(~r/\ACREATE VIEW (?!IF NOT EXISTS)/, "CREATE VIEW IF NOT EXISTS ")
    |> String.replace(~r/\ACREATE DICTIONARY (?!IF NOT EXISTS)/, "CREATE DICTIONARY IF NOT EXISTS ")
  end

  defp read_objects(source) do
    result =
      source.repo.query!(
        """
        SELECT name, engine, create_table_query
        FROM system.tables
        WHERE database = {database:String} AND create_table_query != ''
        ORDER BY name
        """,
        %{"database" => source.database},
        log: false
      )

    rows = Enum.map(result.rows, fn [name, engine, ddl] -> %{name: name, engine: engine, ddl: ddl} end)

    {inner, rest} = Enum.split_with(rows, &String.starts_with?(&1.name, ".inner"))
    {views, tables} = Enum.split_with(rest, &(&1.engine in ["MaterializedView", "View", "LiveView"]))

    %{tables: order_tables(tables), views: views, skipped_inner: inner}
  end

  # `schema_migrations` last, so a run that dies partway does not leave the
  # destination claiming to be fully migrated over a half-cloned schema.
  defp order_tables(tables) do
    {migrations, rest} = Enum.split_with(tables, &(&1.name == "schema_migrations"))
    rest ++ migrations
  end

  defp clone_object(source, target, %{name: name, ddl: ddl}) do
    statement = rewrite(ddl, source.database, target.database)

    case execute(target, statement) do
      :ok ->
        Logger.info("Cloned #{name}")
        {:ok, name}

      {:error, message} ->
        retry_with_pinned_projection(source, target, name, statement, message)
    end
  end

  # A materialized view defined as `SELECT *` is validated against its target
  # when it is created and never again, so the source table can grow columns
  # afterwards and the view keeps working while its stored definition stops
  # being reproducible. Production has one: `test_case_runs_by_inserted_at`
  # declares 20 columns and `test_case_runs` now has 24, so replaying its own
  # DDL fails with `THERE_IS_NO_COLUMN`.
  #
  # Pinning the projection to the columns the view actually declares
  # reproduces exactly what the live view writes, which is the whole point:
  # the destination should end up with the view the source has, not the one
  # its definition would produce today.
  defp retry_with_pinned_projection(source, target, name, statement, message) do
    with true <- String.contains?(message, "THERE_IS_NO_COLUMN"),
         true <- Regex.match?(~r/\bAS\s+SELECT\s+\*/i, statement),
         [_ | _] = columns <- declared_columns(source, name) do
      projection = Enum.map_join(columns, ", ", &Endpoints.quote_ident/1)
      pinned = Regex.replace(~r/(\bAS\s+SELECT\s+)\*/i, statement, "\\1#{projection}", global: false)

      case execute(target, pinned) do
        :ok ->
          Logger.info("Cloned #{name} with its projection pinned to #{length(columns)} declared column(s)")
          {:ok, name}

        {:error, retry_message} ->
          Logger.error("Failed to clone #{name} even with a pinned projection: #{retry_message}")
          {:error, name, retry_message}
      end
    else
      _ ->
        Logger.error("Failed to clone #{name}: #{message}")
        {:error, name, message}
    end
  end

  defp declared_columns(source, name) do
    %{rows: rows} =
      source.repo.query!(
        """
        SELECT name FROM system.columns
        WHERE database = {database:String} AND table = {table:String}
        ORDER BY position
        """,
        %{"database" => source.database, "table" => name},
        log: false
      )

    List.flatten(rows)
  end

  defp execute(target, statement) do
    target.repo.query!(statement, [], log: false)
    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

  # DDL in a `Replicated` database is applied through a queue, so a table can
  # exist in the metadata while its local replica is still initializing.
  # Writing to it in that window fails with `NOT_INITIALIZED`, which is what
  # the migration-version copy hit immediately after creating its own table.
  # This waits for the replica to finish applying everything the clone just
  # queued, and is the difference between a copy that races the DDL and one
  # that follows it.
  defp sync_replica(target) do
    target.repo.query!(
      "SYSTEM SYNC DATABASE REPLICA #{Endpoints.quote_ident(target.database)}",
      [],
      timeout: to_timeout(minute: 5),
      log: false
    )

    target
  end

  # Without this the destination looks like an empty database to
  # `Ecto.Migrator`, which would then replay every migration over a schema
  # that already matches them.
  defp copy_schema_migrations(source, target) do
    # Column types are read from the destination rather than written down
    # here. `ecto_ch` creates `inserted_at` as `DateTime`, not
    # `DateTime64(6)` like the ingest tables, and a hardcoded list is a silent
    # dependency on a schema this module does not own.
    columns = migration_columns(target)
    names = Enum.map_join(columns, ", ", fn {name, _type} -> Endpoints.quote_ident(name) end)
    types = Enum.map(columns, fn {_name, type} -> type end)

    %{rows: rows} =
      source.repo.query!(
        "SELECT #{names} FROM #{Endpoints.quote_ident(source.database)}.schema_migrations ORDER BY version",
        [],
        log: false
      )

    if rows == [] do
      0
    else
      target.repo.query!(
        "INSERT INTO #{Endpoints.quote_ident(target.database)}.schema_migrations (#{names}) FORMAT RowBinary",
        rows,
        types: types,
        log: false
      )

      length(rows)
    end
  end

  defp migration_columns(target) do
    %{rows: rows} =
      target.repo.query!(
        """
        SELECT name, type FROM system.columns
        WHERE database = {database:String} AND table = 'schema_migrations'
        ORDER BY position
        """,
        %{"database" => target.database},
        log: false
      )

    Enum.map(rows, fn [name, type] -> {name, type} end)
  end

  defp summarize(results) do
    %{
      ok: Enum.count(results, &match?({:ok, _}, &1)),
      failed: for({:error, name, message} <- results, do: {name, message})
    }
  end
end
