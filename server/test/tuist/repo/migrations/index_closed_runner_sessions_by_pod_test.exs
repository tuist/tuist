# Each test uses a disposable schema on its own unboxed sandbox connection.
Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261009080000_index_closed_runner_sessions_by_pod.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.IndexClosedRunnerSessionsByPodTest do
  use ExUnit.Case, async: true

  alias DBConnection.ConnectionPool
  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Migration.Runner
  alias Ecto.Migrator
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.IndexClosedRunnerSessionsByPod

  @version 20_261_009_080_000
  @index_name "runner_sessions_closed_pod_name_started_at_index"

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    prefix = "closed_session_index_test_#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"
    Repo.query!(~s(CREATE SCHEMA "#{prefix}"))

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Repo.query!(~s(DROP SCHEMA "#{prefix}" CASCADE))
      after
        Sandbox.checkin(Repo)
      end
    end)

    Repo.query!("""
    CREATE TABLE "#{prefix}".runner_sessions (
      id bigint PRIMARY KEY, pod_name varchar NOT NULL,
      started_at timestamptz NOT NULL, ended_at timestamptz
    )
    """)

    %{prefix: prefix}
  end

  test "creates a valid partial index and removes it on rollback", %{prefix: prefix} do
    options = IndexClosedRunnerSessionsByPod.__migration__()
    assert Keyword.fetch!(options, :disable_ddl_transaction)
    assert Keyword.fetch!(options, :disable_migration_lock)

    migrate(:up, prefix)
    assert [[_, true, true, "pod_name", "started_at", "(ended_at IS NOT NULL)"]] = index_rows(prefix)
    migrate(:down, prefix)
    assert index_rows(prefix) == []
  end

  test "records a completed orphan without rebuilding it", %{prefix: prefix} do
    # Run the DDL without the migrator's history write, matching a disconnected job.
    migrate(:up, prefix)
    [before] = index_rows(prefix)

    assert :ok = Migrator.up(Repo, @version, IndexClosedRunnerSessionsByPod, prefix: prefix, log: false)
    assert Repo.query!(~s(SELECT version FROM "#{prefix}".schema_migrations)).rows == [[@version]]
    assert index_rows(prefix) == [before]
    assert :already_up = Migrator.up(Repo, @version, IndexClosedRunnerSessionsByPod, prefix: prefix, log: false)
    assert :ok = Migrator.down(Repo, @version, IndexClosedRunnerSessionsByPod, prefix: prefix, log: false)
    assert index_rows(prefix) == []
  end

  test "refuses invalid leftovers without dropping them", %{prefix: prefix} do
    Repo.query!("""
    INSERT INTO "#{prefix}".runner_sessions
    VALUES (1, 'pod', '2026-10-01', '2026-10-02'), (2, 'pod', '2026-10-02', '2026-10-03')
    """)

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             Repo.query("""
             CREATE UNIQUE INDEX CONCURRENTLY #{@index_name}
             ON "#{prefix}".runner_sessions (pod_name) WHERE ended_at IS NOT NULL
             """)

    [before] = index_rows(prefix)
    assert Enum.at(before, 1) == false

    assert_raise RuntimeError, ~r/invalid or still building.*server\/priv\/AGENTS.md/, fn ->
      migrate(:up, prefix)
    end

    assert index_rows(prefix) == [before]
  end

  test "refuses a valid index with a different predicate", %{prefix: prefix} do
    Repo.query!("""
    CREATE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".runner_sessions (pod_name, started_at) WHERE ended_at IS NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "refuses a valid index with different keys", %{prefix: prefix} do
    Repo.query!("""
    CREATE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".runner_sessions (started_at, pod_name) WHERE ended_at IS NOT NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "refuses a unique index with otherwise matching keys and predicate", %{prefix: prefix} do
    Repo.query!("""
    CREATE UNIQUE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".runner_sessions (pod_name, started_at) WHERE ended_at IS NOT NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "refuses an index with extra included columns", %{prefix: prefix} do
    Repo.query!("""
    CREATE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".runner_sessions (pod_name, started_at) INCLUDE (id) WHERE ended_at IS NOT NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "refuses an index on a different table in the same schema", %{prefix: prefix} do
    Repo.query!(~s|CREATE TABLE "#{prefix}".other_sessions (LIKE "#{prefix}".runner_sessions)|)

    Repo.query!("""
    CREATE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".other_sessions (pod_name, started_at) WHERE ended_at IS NOT NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "refuses a different collation", %{prefix: prefix} do
    assert [[true]] =
             Repo.query!(
               """
               SELECT attcollation <> 'pg_catalog."C"'::regcollation
               FROM pg_attribute WHERE attrelid = to_regclass($1) AND attname = 'pod_name'
               """,
               [~s("#{prefix}".runner_sessions)]
             ).rows

    Repo.query!("""
    CREATE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".runner_sessions (pod_name COLLATE "C", started_at) WHERE ended_at IS NOT NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "refuses a different operator class", %{prefix: prefix} do
    Repo.query!("""
    CREATE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".runner_sessions (pod_name varchar_pattern_ops, started_at) WHERE ended_at IS NOT NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "refuses a different sort order", %{prefix: prefix} do
    Repo.query!("""
    CREATE INDEX CONCURRENTLY #{@index_name}
    ON "#{prefix}".runner_sessions (pod_name, started_at DESC) WHERE ended_at IS NOT NULL
    """)

    [before] = index_rows(prefix)

    assert_raise RuntimeError, ~r/different definition/, fn -> migrate(:up, prefix) end
    assert index_rows(prefix) == [before]
  end

  test "matches the definition with identifier quoting enabled", %{prefix: prefix} do
    use_dynamic_repo(quote_all_identifiers: "on")
    migrate(:up, prefix)
    [before] = index_rows(prefix)
    migrate(:up, prefix)
    assert index_rows(prefix) == [before]
    migrate(:down, prefix)
    assert index_rows(prefix) == []
  end

  test "resolves an unprefixed migration through the connection search path", %{prefix: prefix} do
    use_dynamic_repo(search_path: ~s("#{prefix}"))
    migrate(:up, nil)
    assert [[_, true, true, "pod_name", "started_at", "(ended_at IS NOT NULL)"]] = index_rows(prefix)
    migrate(:up, nil)
    migrate(:down, nil)
    assert index_rows(prefix) == []
  end

  defp use_dynamic_repo(parameters) do
    config = Repo.config()

    options =
      Keyword.merge(config,
        name: nil,
        pool: ConnectionPool,
        pool_size: 1,
        parameters: Keyword.merge(Keyword.get(config, :parameters, []), parameters)
      )

    Repo.put_dynamic_repo(start_supervised!({Repo, options}))
  end

  defp migrate(direction, prefix) do
    Runner.run(Repo, Repo.config(), @version, IndexClosedRunnerSessionsByPod, :forward, direction, direction,
      prefix: prefix,
      log: false
    )
  end

  defp index_rows(prefix) do
    Repo.query!(
      """
      SELECT i.indexrelid::bigint, i.indisvalid, i.indisready,
             pg_get_indexdef(i.indexrelid, 1, true),
             CASE WHEN i.indnatts >= 2 THEN pg_get_indexdef(i.indexrelid, 2, true) END,
             pg_get_expr(i.indpred, i.indrelid)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND c.relname = $2
      """,
      [prefix, @index_name]
    ).rows
  end
end
