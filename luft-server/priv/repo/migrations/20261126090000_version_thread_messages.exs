defmodule LuftServer.Repo.Migrations.VersionThreadMessages do
  use Ecto.Migration

  # Every message records the thread revision that last changed it, so a
  # client that has seen revision N receives exactly the messages with a
  # version above N. The trigger takes the next revision while locking the
  # thread row, which every thread write already locks: versions in one thread
  # therefore commit in order, and a cursor can never skip a row that commits
  # later with a lower version.
  # Only columns clients see stamp a version. Clearing `author_session_id`
  # when a session ends must not take thread locks or resend messages.
  @visible ~w(request_id position kind author_id body attachments tool_name tool_state
              suggestions suggestion_icons card_size card_source decision progress)

  def up do
    alter table(:thread_messages) do
      add :version, :bigint, null: false, default: 0
    end

    # A message's position is the revision it was appended at, not the last
    # one that changed it, so existing rows take their thread's revision: a
    # client's stored revision can then never be above an earlier edit.
    execute """
    UPDATE thread_messages m SET version = t.revision FROM threads t WHERE t.id = m.thread_id
    """

    execute """
    CREATE FUNCTION thread_messages_version() RETURNS trigger AS $$
    DECLARE
      next bigint;
    BEGIN
      SELECT revision + 1 INTO next
        FROM threads WHERE id = NEW.thread_id FOR NO KEY UPDATE;
      -- Without a thread, the foreign key rejects the row.
      NEW.version := COALESCE(next, 0);
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER thread_messages_version
      BEFORE INSERT OR UPDATE OF #{Enum.join(@visible, ", ")} ON thread_messages
      FOR EACH ROW EXECUTE FUNCTION thread_messages_version()
    """

    create index(:thread_messages, [:thread_id, :version])
  end

  def down do
    drop index(:thread_messages, [:thread_id, :version])
    execute "DROP TRIGGER thread_messages_version ON thread_messages"
    execute "DROP FUNCTION thread_messages_version()"

    alter table(:thread_messages) do
      remove :version
    end
  end
end
