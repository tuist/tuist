defmodule Tuist.Repo.Migrations.IndexClosedRunnerSessionsByPod do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true
  @index_name :runner_sessions_closed_pod_name_started_at_index

  def up do
    table =
      case prefix() do
        nil -> "runner_sessions"
        schema -> ~s("#{String.replace(schema, "\"", "\"\"")}".runner_sessions)
      end

    # The per-column form omits collation, operator classes, and ordering.
    # Compare the full canonical definition, with PostgreSQL's identifier quoting.
    # A future change to PostgreSQL's deparsing fails closed rather than adopting a mismatch.
    existing =
      repo().query!(
        """
        SELECT i.indisvalid, i.indisready, i.indislive,
               pg_get_indexdef(i.indexrelid) =
                 format('CREATE INDEX %I ON %I.%I USING %I (%I, %I) WHERE (%I IS NOT NULL)',
                        idx.relname, ns.nspname, 'runner_sessions', 'btree', 'pod_name', 'started_at', 'ended_at')
        FROM pg_index i
        JOIN pg_class idx ON idx.oid = i.indexrelid
        JOIN pg_namespace ns ON ns.oid = idx.relnamespace
        WHERE idx.relname = $2
          AND idx.relnamespace = (SELECT relnamespace FROM pg_class WHERE oid = to_regclass($1))
        """,
        [table, Atom.to_string(@index_name)]
      ).rows

    case existing do
      [] ->
        create index(:runner_sessions, [:pod_name, :started_at],
                 name: @index_name,
                 where: "ended_at IS NOT NULL",
                 concurrently: true
               )

      [[true, true, true, true]] ->
        # A disconnected migration job may leave a completed index without recording its version.
        :ok

      [[valid, ready, live, _]] when not valid or not ready or not live ->
        raise "#{@index_name} is invalid or still building; see server/priv/AGENTS.md for authorized recovery"

      _ ->
        raise "#{@index_name} already exists with a different definition; inspect it before retrying the migration"
    end
  end

  def down do
    drop index(:runner_sessions, [:pod_name, :started_at], name: @index_name, concurrently: true)
  end
end
