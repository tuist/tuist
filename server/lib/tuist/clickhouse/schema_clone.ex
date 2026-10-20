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
  alias Tuist.ClickHouse.Tables

  require Logger

  @engine_families ~w(MergeTree ReplacingMergeTree AggregatingMergeTree SummingMergeTree CollapsingMergeTree VersionedCollapsingMergeTree GraphiteMergeTree)

  # Skip indexes that reconcile also builds for the destination's existing
  # parts, rather than leaving them to new parts and merges. Kept explicit:
  # each entry is an index a hot read depends on, on a table whose rows are
  # few enough that rebuilding it one partition at a time is cheap.
  @materialized_on_reconcile MapSet.new([{"gradle_builds", "idx_id"}, {"mix_builds", "idx_id"}])

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
  Brings the destination back in line with the source, for the objects that
  have appeared or changed since it was cloned.

  Migrations run against the source only, so from the moment of the clone the
  two schemas drift apart, and the drift is not survivable: a column the
  destination lacks costs a dropped mirror write while the source is still
  primary, and breaks the ingest path the moment it is not.

  Reconciling from the source's own DDL rather than replaying the migrations,
  because a replay changes where the statements go without changing what they
  say. The ingest migrations create plain `MergeTree` tables, and this
  destination refuses them outright:

      Code: 56. Only tables with a Replicated engine ... are allowed in a
      Replicated database. (UNKNOWN_STORAGE)

  The clone already solves that by taking the source's definition and
  rewriting the engine family, so the same path is reused here. What it cannot
  see is a change to an object that already exists on both sides, which is why
  columns are reconciled separately.

  Deliberately additive. It creates what is missing and adds columns that are
  missing, and it does not drop or retype anything: those are rare, they are
  not always recoverable, and a schema reconciler that can delete is a worse
  thing to run unattended on every deploy than a little drift is.
  """
  def reconcile(opts \\ []) do
    Endpoints.with_repos(opts, fn source, target ->
      drift = Tables.schema_drift(source, target)

      created = create_missing(source, target, drift.missing_on_destination)
      added = add_missing_columns(source, target, drift.differing_columns)
      indices = reconcile_indices(source, target)

      report = %{
        created: created,
        columns_added: added,
        indices_added: indices.added,
        indices_mismatched: indices.mismatched,
        indices_materialized: indices.materialized
      }

      Logger.info("ClickHouse schema reconcile: #{inspect(report)}")
      {:ok, report}
    end)
  end

  defp create_missing(_source, _target, []), do: []

  defp create_missing(source, target, names) do
    wanted = MapSet.new(names)
    objects = read_objects(source)

    # Tables before views, because a view's `SELECT` refers to the table it
    # reads and cannot be created before it.
    (objects.tables ++ objects.views)
    |> Enum.filter(&MapSet.member?(wanted, &1.name))
    |> Enum.map(&clone_object(source, target, &1))
    |> Enum.map(fn
      {:ok, name} -> name
      {:error, name, message} -> "#{name} (failed: #{message})"
    end)
  end

  defp add_missing_columns(source, target, differing) do
    Enum.flat_map(differing, fn {table, only_on_source, only_on_destination} ->
      retyped = retyped_columns(only_on_source, only_on_destination)

      if retyped != [] do
        # A column whose type changed appears on both sides, and adding it
        # would fail because it is already there. Left alone and named, since
        # a type change needs a human to decide whether the data survives it.
        Logger.error("#{table}: column type changed, not reconciled: #{inspect(retyped)}")
      end

      {positions, clauses} = source_columns(source, table)

      only_on_source
      |> Enum.reject(&(name_of(&1) in retyped))
      |> in_source_order(positions)
      |> Enum.map(fn column ->
        statement = add_column_statement(target.database, table, column, positions, clauses)

        case execute(target, statement) do
          :ok ->
            "#{table}.#{name_of(column)}"

          {:error, message} ->
            Logger.error("Could not add #{table}.#{name_of(column)}: #{message}")
            "#{table}.#{name_of(column)} (failed)"
        end
      end)
    end)
  end

  # Skip indexes are part of a table's DDL, so a cloned or newly created table
  # already has them, but an index a later migration adds to an existing table
  # (`ALTER TABLE ... ADD INDEX` through `execute/1`, which no repository
  # override sees) never reaches the destination otherwise. Run after
  # `create_missing/3`, so tables created in this pass are compared with the
  # indexes their DDL already gave them.
  #
  # Additive like the columns: an index only the destination has is left
  # alone, and one defined differently on each side is reported, not
  # replaced, because rebuilding it is a decision for a human. Materialization
  # of the allowlisted indexes is re-checked on every run rather than only
  # when the index is added, so a run that added the index but failed to
  # schedule its mutations is completed by the next one.
  defp reconcile_indices(source, target) do
    source_indices = skipping_indices(source)
    target_indices = skipping_indices(target)

    added =
      source_indices
      |> missing_indices(target_indices, table_names(target))
      |> Enum.flat_map(fn index ->
        case execute(target, add_index_statement(target.database, index)) do
          :ok ->
            ["#{index.table}.#{index.name}"]

          {:error, message} ->
            Logger.error("Could not add index #{index.table}.#{index.name}: #{message}")
            ["#{index.table}.#{index.name} (failed)"]
        end
      end)

    mismatched =
      for {source_index, target_index} <- mismatched_indices(source_indices, target_indices) do
        Logger.error(
          "Index #{source_index.table}.#{source_index.name} differs: source #{index_definition(source_index)}, " <>
            "destination #{index_definition(target_index)}; not reconciled"
        )

        "#{source_index.table}.#{source_index.name}"
      end

    %{added: added, mismatched: mismatched, materialized: materialize_pending(target)}
  end

  @doc """
  Pairs of `{source, destination}` definitions for indexes both sides have
  under the same table and name but define differently.
  """
  def mismatched_indices(source_indices, target_indices) do
    by_name = Map.new(target_indices, &{{&1.table, &1.name}, &1})

    for source_index <- source_indices,
        target_index = Map.get(by_name, {source_index.table, source_index.name}),
        target_index != nil,
        index_definition(source_index) != index_definition(target_index),
        do: {source_index, target_index}
  end

  defp index_definition(index), do: "#{index.expr} TYPE #{index.type} GRANULARITY #{index.granularity}"

  # For each allowlisted index the destination has, schedules one mutation per
  # partition that still holds parts without index data. A mutation already
  # pending for the index is left to finish, and one that keeps failing is
  # reported rather than scheduled again.
  defp materialize_pending(target) do
    present = target |> skipping_indices() |> Enum.group_by(& &1.table, & &1.name)

    Enum.flat_map(@materialized_on_reconcile, fn {table, name} ->
      indexes = Map.get(present, table, [])

      cond do
        name not in indexes ->
          []

        indexes != [name] ->
          # Per-part index sizes cover all of a table's skip indexes, so
          # unindexed parts can only be told apart when this is the only one.
          Logger.warning("#{table}.#{name}: cannot verify materialization, #{table} has other skip indexes")
          []

        true ->
          materialize_unindexed(target, table, name)
      end
    end)
  end

  defp materialize_unindexed(target, table, name) do
    case pending_materializations(target.repo, target.database, table, name) do
      [] ->
        target.repo
        |> unindexed_partition_ids(target.database, table)
        |> then(&materialize_index_statements(target.database, table, name, &1))
        |> Enum.flat_map(fn statement ->
          case execute(target, statement) do
            :ok ->
              ["#{table}.#{name}"]

            {:error, message} ->
              Logger.error("Could not materialize index #{table}.#{name}: #{message}")
              ["#{table}.#{name} (failed)"]
          end
        end)
        |> Enum.uniq()

      failures ->
        for reason <- failures, reason != "" do
          Logger.error("Materializing #{table}.#{name} keeps failing: #{reason}")
        end

        []
    end
  end

  @doc """
  The active partitions of `table` holding parts with rows but no skip index
  data, which is what a part written before `ADD INDEX` and not yet
  materialized looks like. Only meaningful for a table with a single skip
  index, because the per-part sizes cover all of them.
  """
  def unindexed_partition_ids(repo, database, table) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT DISTINCT partition_id FROM system.parts
        WHERE database = {database:String} AND table = {table:String} AND active
          AND rows > 0 AND secondary_indices_compressed_bytes = 0
        ORDER BY partition_id
        """,
        %{"database" => database, "table" => table},
        log: false
      )

    Enum.map(rows, &hd/1)
  end

  @doc """
  The latest failure reason of each unfinished `MATERIALIZE INDEX` mutation
  for `name` on `table`, `""` while one is still running normally.
  """
  def pending_materializations(repo, database, table, name) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT latest_fail_reason FROM system.mutations
        WHERE database = {database:String} AND table = {table:String} AND NOT is_done
          AND positionCaseInsensitive(command, 'MATERIALIZE INDEX') > 0
          AND position(command, {name:String}) > 0
        """,
        %{"database" => database, "table" => table, "name" => name},
        log: false
      )

    Enum.map(rows, &hd/1)
  end

  @doc """
  The source's skip indexes that the destination lacks, on tables both sides
  have. Compared by table and index name only.

  Public because the selection is the part worth testing without a
  ClickHouse to talk to.
  """
  def missing_indices(source_indices, target_indices, target_tables) do
    present = MapSet.new(target_indices, &{&1.table, &1.name})

    Enum.filter(source_indices, fn index ->
      MapSet.member?(target_tables, index.table) and not MapSet.member?(present, {index.table, index.name})
    end)
  end

  @doc """
  The metadata-only `ALTER` that adds one skip index as the source defines it.
  It covers parts written from then on; existing parts are only indexed by a
  separate `MATERIALIZE INDEX`.
  """
  def add_index_statement(database, %{table: table, name: name, expr: expr, type: type, granularity: granularity}) do
    "ALTER TABLE #{Endpoints.quote_ident(database)}.#{Endpoints.quote_ident(table)} " <>
      "ADD INDEX IF NOT EXISTS #{Endpoints.quote_ident(name)} #{expr} TYPE #{type} GRANULARITY #{granularity}"
  end

  @doc """
  One `MATERIALIZE INDEX` per partition, each an asynchronous mutation.

  A whole-table `MATERIALIZE INDEX` is a single mutation over every part, so
  the table's size, not its retention, decides how much it does at once. One
  mutation per partition bounds each unit of work to one partition, a
  mutation that builds an index reads only the indexed columns, and
  `mutations_sync = 0` returns before any of it runs, so neither a deploy nor
  a reconcile waits on it.
  """
  def materialize_index_statements(database, table, name, partition_ids) do
    Enum.map(partition_ids, fn partition_id ->
      "ALTER TABLE #{Endpoints.quote_ident(database)}.#{Endpoints.quote_ident(table)} " <>
        "MATERIALIZE INDEX #{Endpoints.quote_ident(name)} IN PARTITION ID '#{escape_literal(partition_id)}' " <>
        "SETTINGS mutations_sync = 0"
    end)
  end

  @doc """
  The active partition IDs of `table`, for `materialize_index_statements/4`.
  """
  def partition_ids(repo, database, table) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT DISTINCT partition_id FROM system.parts
        WHERE database = {database:String} AND table = {table:String} AND active
        ORDER BY partition_id
        """,
        %{"database" => database, "table" => table},
        log: false
      )

    Enum.map(rows, &hd/1)
  end

  defp skipping_indices(endpoint) do
    %{rows: rows} =
      endpoint.repo.query!(
        """
        SELECT table, name, expr, type_full, granularity FROM system.data_skipping_indices
        WHERE database = {database:String} AND table NOT LIKE '.inner%'
        """,
        %{"database" => endpoint.database},
        log: false
      )

    Enum.map(rows, fn [table, name, expr, type, granularity] ->
      %{table: table, name: name, expr: expr, type: type, granularity: granularity}
    end)
  end

  defp table_names(endpoint) do
    %{rows: rows} =
      endpoint.repo.query!(
        "SELECT name FROM system.tables WHERE database = {database:String}",
        %{"database" => endpoint.database},
        log: false
      )

    MapSet.new(rows, &hd/1)
  end

  defp escape_literal(value), do: String.replace(value, ["\\", "'"], fn char -> "\\" <> char end)

  @doc """
  The missing columns in the order the source has them. Each one is added
  after its predecessor on the source (`add_column_statement/4`), so a run of
  new adjacent columns only lands when they are added front to back: added in
  any other order, each column after the first refers to one that is not
  there yet and fails.
  """
  def in_source_order(columns, positions) do
    index = positions |> Enum.with_index() |> Map.new()
    Enum.sort_by(columns, &Map.get(index, name_of(&1), length(positions)))
  end

  defp retyped_columns(only_on_source, only_on_destination) do
    destination_names = MapSet.new(only_on_destination, &name_of/1)

    only_on_source |> Enum.map(&name_of/1) |> Enum.filter(&MapSet.member?(destination_names, &1))
  end

  @doc """
  The `ALTER` that adds one column back, in the position the source has it.

  Position is not cosmetic here: the backfill copies with `SELECT *`, which
  maps columns by position, so a column appended to the end of one server and
  sitting in the middle of the other would copy every later column into the
  wrong place.

  The column keeps the source's default and codec (`clauses`, keyed by name).
  Without the default, rows the destination already holds read the type's
  zero value where the source reads the default, which is just as silent.

  Public because that is the part worth testing without a ClickHouse to talk
  to, and because the failure it prevents is silent.
  """
  def add_column_statement(database, table, column, positions, clauses \\ %{}) do
    [name, type] = String.split(column, " ", parts: 2)

    definition = Enum.join([type | List.wrap(Map.get(clauses, name))], " ")

    prefix =
      "ALTER TABLE #{Endpoints.quote_ident(database)}.#{Endpoints.quote_ident(table)} ADD COLUMN IF NOT EXISTS #{Endpoints.quote_ident(name)} #{definition}"

    case previous_column(name, positions) do
      nil -> "#{prefix} FIRST"
      previous -> "#{prefix} AFTER #{Endpoints.quote_ident(previous)}"
    end
  end

  defp previous_column(name, positions) do
    case Enum.find_index(positions, &(&1 == name)) do
      nil -> nil
      0 -> nil
      index -> Enum.at(positions, index - 1)
    end
  end

  defp name_of(column), do: column |> String.split(" ", parts: 2) |> hd()

  defp source_columns(source, table) do
    %{rows: rows} =
      source.repo.query!(
        """
        SELECT name, default_kind, default_expression, compression_codec FROM system.columns
        WHERE database = {database:String} AND table = {table:String}
        ORDER BY position
        """,
        %{"database" => source.database, "table" => table},
        log: false
      )

    clauses =
      for [name, kind, expression, codec] <- rows,
          clause = column_clause(kind, expression, codec),
          clause != "",
          into: %{},
          do: {name, clause}

    {Enum.map(rows, &hd/1), clauses}
  end

  @doc false
  def column_clause(kind, expression, codec) do
    [if(kind != "", do: "#{kind} #{expression}"), if(codec != "", do: codec)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
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
