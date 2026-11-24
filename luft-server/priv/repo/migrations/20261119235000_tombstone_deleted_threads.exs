defmodule LuftServer.Repo.Migrations.TombstoneDeletedThreads do
  use Ecto.Migration

  def up do
    execute """
    CREATE FUNCTION luft_tombstone_thread_session() RETURNS trigger AS $$
    BEGIN
      INSERT INTO agent_sessions (id, kind, wanted, deleted_at, inserted_at, updated_at)
      VALUES (OLD.id::text, 'thread', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (id) DO UPDATE
        SET wanted = false, deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER luft_thread_session_deleted AFTER DELETE ON threads
    FOR EACH ROW EXECUTE FUNCTION luft_tombstone_thread_session();
    """
  end

  def down do
    execute "DROP TRIGGER luft_thread_session_deleted ON threads"
    execute "DROP FUNCTION luft_tombstone_thread_session()"
  end
end
