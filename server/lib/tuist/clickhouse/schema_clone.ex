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
      ensure_database(target)

      objects = read_objects(source)

      Logger.info(
        "Cloning #{length(objects.tables)} table(s) and #{length(objects.views)} view(s) from #{source.database} into #{target.database}"
      )

      tables = Enum.map(objects.tables, &clone_object(target, &1, source.database, target.database))
      views = Enum.map(objects.views, &clone_object(target, &1, source.database, target.database))

      report = %{
        tables: summarize(tables),
        views: summarize(views),
        migrations_copied: copy_schema_migrations(source, target),
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

  # A `Replicated` database is what makes DDL reach every replica without each
  # migration carrying `ON CLUSTER`. It is required even at one replica,
  # because that is the shape the engines above expect.
  defp ensure_database(target) do
    target.repo.query!(
      """
      CREATE DATABASE IF NOT EXISTS #{Endpoints.quote_ident(target.database)}
      ENGINE = Replicated('/clickhouse/databases/#{target.database}', '{shard}', '{replica}')
      """,
      [],
      log: false
    )

    :ok
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

  defp clone_object(target, %{name: name, ddl: ddl}, source_database, target_database) do
    statement = rewrite(ddl, source_database, target_database)

    target.repo.query!(statement, [], log: false)
    Logger.info("Cloned #{name}")
    {:ok, name}
  rescue
    error ->
      Logger.error("Failed to clone #{name}: #{Exception.message(error)}")
      {:error, name, Exception.message(error)}
  end

  # Without this the destination looks like an empty database to
  # `Ecto.Migrator`, which would then replay every migration over a schema
  # that already matches them.
  defp copy_schema_migrations(source, target) do
    %{rows: rows} =
      source.repo.query!(
        "SELECT version, inserted_at FROM #{Endpoints.quote_ident(source.database)}.schema_migrations ORDER BY version",
        [],
        log: false
      )

    if rows == [] do
      0
    else
      target.repo.query!(
        "INSERT INTO #{Endpoints.quote_ident(target.database)}.schema_migrations (version, inserted_at) FORMAT RowBinary",
        rows,
        types: ["Int64", "DateTime64(6)"],
        log: false
      )

      length(rows)
    end
  end

  defp summarize(results) do
    %{
      ok: Enum.count(results, &match?({:ok, _}, &1)),
      failed: for({:error, name, message} <- results, do: {name, message})
    }
  end
end
