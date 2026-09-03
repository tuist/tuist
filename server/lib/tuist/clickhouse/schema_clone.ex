defmodule Tuist.ClickHouse.SchemaClone do
  @moduledoc """
  Clones a ClickHouse schema from one server to another, rewriting the engine
  family so the destination's tables are replicated.

  This is how the in-cluster ClickHouse gets its schema during the migration
  off ClickHouse Cloud, and it exists because replaying the 227 ingest
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

  alias Tuist.Environment

  require Logger

  # Ordinary tables first so that a materialized view's explicit `TO` target
  # exists before the view that writes into it.
  @engine_families ~w(MergeTree ReplacingMergeTree AggregatingMergeTree SummingMergeTree CollapsingMergeTree VersionedCollapsingMergeTree GraphiteMergeTree)

  @doc """
  Clones the schema of `source_url` into `target_url`.

  Idempotent: every statement is emitted with `IF NOT EXISTS`, so a partial
  run is completed by running it again. Returns a report of what it did.
  """
  def run(opts \\ []) do
    source_url = Keyword.get_lazy(opts, :source_url, fn -> Environment.clickhouse_url() end)
    target_url = Keyword.get_lazy(opts, :target_url, fn -> Environment.clickhouse_bare_metal_url() end)

    cond do
      is_nil(target_url) or target_url == "" ->
        {:error, :no_target_configured}

      is_nil(source_url) or source_url == "" ->
        {:error, :no_source_configured}

      true ->
        clone(parse_url!(source_url, "source"), parse_url!(target_url, "target"))
    end
  end

  defp clone(source, target) do
    # The target may not exist yet. The migration release task runs as a
    # pre-upgrade hook, which is before Helm applies the ClickHouse
    # StatefulSet, so on the deploy that first introduces it there is nothing
    # listening. That is a distinct outcome from a failed clone, and the
    # caller treats it as such: the next deploy finds the server up and
    # clones then.
    with {:ok, source_conn} <- connect(source),
         {:ok, target_conn} <- connect(target) do
      ensure_database(target_conn, target.database)

      objects = read_objects(source_conn, source.database)

      Logger.info(
        "Cloning #{length(objects.tables)} table(s) and #{length(objects.views)} view(s) from #{source.database} to #{target.database}"
      )

      tables = Enum.map(objects.tables, &clone_object(target_conn, &1, source.database, target.database))
      views = Enum.map(objects.views, &clone_object(target_conn, &1, source.database, target.database))

      migrations = copy_schema_migrations(source_conn, target_conn, source.database, target.database)

      report = %{
        tables: summarize(tables),
        views: summarize(views),
        migrations_copied: migrations,
        skipped_inner_tables: objects.skipped_inner
      }

      Logger.info("Schema clone finished: #{inspect(report)}")
      {:ok, report}
    end
  end

  defp connect(target) do
    case start_connection(target) do
      {:ok, conn} ->
        # Starting the pool does not prove the server answers, so ask it
        # something before reporting the connection usable.
        case Ch.query(conn, "SELECT 1") do
          {:ok, _} -> {:ok, conn}
          {:error, error} -> {:error, {:target_unreachable, Exception.message(error)}}
        end

      {:error, error} ->
        {:error, {:target_unreachable, inspect(error)}}
    end
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

  # `Shared` and `Replicated` cover the engine; a plain `MergeTree` source
  # (a self-hosted install, or local development) still has to become
  # replicated, and is matched only when it is not already `Replicated`.
  defp requalify_database(ddl, source_database, target_database) when source_database == target_database, do: ddl

  defp requalify_database(ddl, source_database, target_database) do
    ddl
    |> String.replace("#{quote_ident(source_database)}.", "#{quote_ident(target_database)}.")
    |> String.replace("#{source_database}.", "#{target_database}.")
  end

  defp add_if_not_exists(ddl) do
    ddl
    |> String.replace(~r/\ACREATE TABLE (?!IF NOT EXISTS)/, "CREATE TABLE IF NOT EXISTS ")
    |> String.replace(~r/\ACREATE MATERIALIZED VIEW (?!IF NOT EXISTS)/, "CREATE MATERIALIZED VIEW IF NOT EXISTS ")
    |> String.replace(~r/\ACREATE VIEW (?!IF NOT EXISTS)/, "CREATE VIEW IF NOT EXISTS ")
    |> String.replace(~r/\ACREATE DICTIONARY (?!IF NOT EXISTS)/, "CREATE DICTIONARY IF NOT EXISTS ")
  end

  defp ensure_database(conn, database) do
    # A `Replicated` database is what makes DDL reach every replica without
    # each migration carrying `ON CLUSTER`. It is required even at one
    # replica, because that is the shape the engines above expect.
    statement = """
    CREATE DATABASE IF NOT EXISTS #{quote_ident(database)}
    ENGINE = Replicated('/clickhouse/databases/#{database}', '{shard}', '{replica}')
    """

    {:ok, _} = Ch.query(conn, statement)
    :ok
  end

  defp read_objects(conn, database) do
    {:ok, result} =
      Ch.query(
        conn,
        """
        SELECT name, engine, create_table_query
        FROM system.tables
        WHERE database = {database:String}
          AND create_table_query != ''
        ORDER BY name
        """,
        %{"database" => database}
      )

    rows = Enum.map(result.rows, fn [name, engine, ddl] -> %{name: name, engine: engine, ddl: ddl} end)

    {inner, rest} = Enum.split_with(rows, &String.starts_with?(&1.name, ".inner"))
    {views, tables} = Enum.split_with(rest, &(&1.engine in ["MaterializedView", "View", "LiveView"]))

    %{
      tables:
        Enum.reject(tables, &(&1.name == "schema_migrations")) ++ Enum.filter(tables, &(&1.name == "schema_migrations")),
      views: views,
      skipped_inner: Enum.map(inner, & &1.name)
    }
  end

  defp clone_object(conn, %{name: name, ddl: ddl}, source_database, target_database) do
    statement = rewrite(ddl, source_database, target_database)

    case Ch.query(conn, statement) do
      {:ok, _} ->
        Logger.info("Cloned #{name}")
        {:ok, name}

      {:error, error} ->
        Logger.error("Failed to clone #{name}: #{Exception.message(error)}")
        {:error, name, Exception.message(error)}
    end
  end

  # Without this the destination looks like an empty database to
  # `Ecto.Migrator`, which would then try to replay all 227 migrations over a
  # schema that already matches them.
  defp copy_schema_migrations(source_conn, target_conn, source_database, target_database) do
    {:ok, result} =
      Ch.query(
        source_conn,
        "SELECT version, inserted_at FROM #{quote_ident(source_database)}.schema_migrations ORDER BY version"
      )

    rows = result.rows

    if rows == [] do
      0
    else
      {:ok, _} =
        Ch.query(
          target_conn,
          "INSERT INTO #{quote_ident(target_database)}.schema_migrations (version, inserted_at) FORMAT RowBinary",
          rows,
          types: ["Int64", "DateTime64(6)"]
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

  defp start_connection(%{} = target) do
    Ch.start_link(
      scheme: target.scheme,
      hostname: target.hostname,
      port: target.port,
      database: target.database,
      username: target.username,
      password: target.password,
      # A clone is a long series of DDL statements, and a `Replicated`
      # database acknowledges each one only once the distributed DDL queue
      # has processed it.
      timeout: to_timeout(minute: 5)
    )
  end

  defp parse_url!(url, role) do
    uri = URI.parse(url)

    if !(uri.scheme in ["http", "https"] and is_binary(uri.host)) do
      raise ArgumentError, "#{role} ClickHouse URL must be an absolute http(s) URL, got: #{inspect(url)}"
    end

    {username, password} = credentials(uri.userinfo)

    %{
      scheme: uri.scheme,
      hostname: uri.host,
      port: uri.port || default_port(uri.scheme),
      database: database(uri.path),
      username: username,
      password: password
    }
  end

  defp credentials(nil), do: {"default", ""}

  defp credentials(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {user, ""}
      [user, password] -> {user, password}
    end
  end

  defp default_port("https"), do: 8443
  defp default_port(_scheme), do: 8123

  defp database(path) do
    case path |> to_string() |> String.trim_leading("/") do
      "" -> "default"
      database -> database
    end
  end

  defp quote_ident(name) do
    "`" <> String.replace(name, "`", "``") <> "`"
  end
end
