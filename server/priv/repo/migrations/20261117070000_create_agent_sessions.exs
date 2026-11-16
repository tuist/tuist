# New, empty tables: their indexes block no existing reads or writes.
# excellent_migrations:safety-assured-for-this-file index_not_concurrently
defmodule Tuist.Repo.Migrations.CreateAgentSessions do
  use Ecto.Migration

  def change do
    # A durable Condukt session, hosted by one `agents` pod at a time under a
    # lease. `kind` names the product feature that owns it (`thread`, ...),
    # whose module starts it. The session's conversation and journal live in
    # object storage (`Tuist.Agents.SessionStore`); this row is its lease.
    create table(:agent_sessions, primary_key: false) do
      add :id, :text, primary_key: true
      add :kind, :text, null: false
      add :wanted, :boolean, null: false, default: false
      add :wanted_at, :timestamptz
      # Counts wants, so a host that saw the session idle releases it only if
      # no want arrived since it last looked.
      add :want_seq, :bigint, null: false, default: 0
      add :epoch, :bigint, null: false, default: 0
      add :host, :text
      add :lease_expires_at, :timestamptz
      # Set when what owns the session was deleted: the session's objects
      # are deleted, then the row (`Tuist.Agents.Workers.PurgeDeletedSessionsWorker`).
      add :deleted_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    # What hosts claim: sessions that want a host, oldest first.
    create index(:agent_sessions, [:wanted_at], where: "wanted")
    create index(:agent_sessions, [:host])
    create index(:agent_sessions, [:deleted_at], where: "deleted_at IS NOT NULL")

    # Threads with an inference run queued from before sessions were hosted:
    # their sessions want a host. A running one is still a previous pod's to
    # finish; if that pod stops first, its Oban job comes back to a new pod,
    # which wants the session then (`Tuist.Threads.Worker`). The epoch starts
    # at the run's attempt, so a host's claim is later.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      INSERT INTO agent_sessions (id, kind, wanted, wanted_at, want_seq, epoch, inserted_at, updated_at)
      SELECT r.thread_id::text, 'thread', true, CURRENT_TIMESTAMP, 1, max(r.attempt), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM thread_runs r
      WHERE r.kind <> 'ship' AND r.status = 'queued'
      GROUP BY r.thread_id
      ON CONFLICT (id) DO NOTHING
      """,
      ""
    )

    # A session has no foreign key to its owner, since kinds differ in what
    # owns them. A thread's session follows the thread's retention: deleting
    # the thread, as its account or owner cascades, marks the session
    # deleted, and a sweep deletes its objects and then the row. A trigger
    # cannot reach object storage, so it only marks.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      CREATE FUNCTION delete_thread_agent_session() RETURNS trigger AS $$
      BEGIN
        UPDATE agent_sessions SET deleted_at = CURRENT_TIMESTAMP, wanted = false
        WHERE kind = 'thread' AND id = OLD.id::text;
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql
      """,
      "DROP FUNCTION delete_thread_agent_session()"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      CREATE TRIGGER delete_thread_agent_session AFTER DELETE ON threads
        FOR EACH ROW EXECUTE FUNCTION delete_thread_agent_session()
      """,
      "DROP TRIGGER delete_thread_agent_session ON threads"
    )
  end
end
