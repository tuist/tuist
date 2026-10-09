# From server/: mise exec -- elixir -pa '_build/test/lib/*/ebin' benchmarks/check_closed_session_index.exs
# Uses only the local Unix socket and a newly created, disposable schema.
alias ClosedSessionIndexCheck.Repo
alias Tuist.Repo.Migrations.IndexClosedRunnerSessionsByPod

Mix.start()
{:ok, _} = Application.ensure_all_started(:ecto_sql)

defmodule ClosedSessionIndexCheck.Repo do
  use Ecto.Repo, otp_app: :closed_session_index_check, adapter: Ecto.Adapters.Postgres
end

Code.require_file("../priv/repo/migrations/20261009080000_index_closed_runner_sessions_by_pod.exs", __DIR__)

{:ok, _} = Repo.start_link(socket_dir: "/tmp", username: System.fetch_env!("USER"), database: "postgres", pool_size: 2)

[[nil, false, nil, false]] =
  Repo.query!("""
  SELECT inet_server_addr(), pg_is_in_recovery(), to_regclass('public.runner_sessions')::text,
         EXISTS (SELECT 1 FROM pg_stat_replication)
  """).rows

prefix = "closed_session_index_check_#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"
Repo.query!(~s(CREATE SCHEMA "#{prefix}"))

try do
  Repo.query!("""
  CREATE TABLE "#{prefix}".runner_sessions (
    id bigint PRIMARY KEY, pod_name varchar NOT NULL, started_at timestamptz NOT NULL, ended_at timestamptz
  )
  """)

  Repo.query!("""
  INSERT INTO "#{prefix}".runner_sessions
  SELECT i, 'pod-' || (i / 3), '2026-10-01'::timestamptz + i * interval '1 second',
         CASE WHEN i % 1000 = 0 THEN NULL ELSE '2026-10-01'::timestamptz + (i + 60) * interval '1 second' END
  FROM generate_series(1, 150000) AS i
  """)

  started_at = System.monotonic_time(:millisecond)
  :ok = Ecto.Migrator.up(Repo, 20_261_009_080_000, IndexClosedRunnerSessionsByPod, prefix: prefix, log: false)
  IO.puts("Concurrent migration (150,000 synthetic rows): #{System.monotonic_time(:millisecond) - started_at} ms")

  [[true, true, definition]] =
    Repo.query!(
      """
      SELECT i.indisvalid, i.indisready, pg_get_indexdef(i.indexrelid)
      FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname=$1 AND c.relname='runner_sessions_closed_pod_name_started_at_index'
      """,
      [prefix]
    ).rows

  true = String.contains?(definition, "(pod_name, started_at)")
  true = String.contains?(definition, "WHERE (ended_at IS NOT NULL)")

  started_at = System.monotonic_time(:millisecond)
  :ok = Ecto.Migrator.down(Repo, 20_261_009_080_000, IndexClosedRunnerSessionsByPod, prefix: prefix, log: false)
  IO.puts("Concurrent rollback: #{System.monotonic_time(:millisecond) - started_at} ms")

  [[0]] =
    Repo.query!("SELECT count(*) FROM pg_indexes WHERE schemaname=$1 AND indexname=$2", [
      prefix,
      "runner_sessions_closed_pod_name_started_at_index"
    ]).rows

  IO.puts("Concurrent migration and rollback passed")
after
  Repo.query!(~s(DROP SCHEMA "#{prefix}" CASCADE))
end
