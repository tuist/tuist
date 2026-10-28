defmodule Atlas.Repo.Migrations.AllowMultiplePrivateOrbitThreads do
  use Ecto.Migration

  def up do
    alter table(:orbit_threads) do
      add :request_id, :uuid
    end

    create unique_index(:orbit_threads, [:owner_id, :request_id],
             name: :orbit_threads_private_request_index,
             where: "kind = 'private' AND request_id IS NOT NULL"
           )

    create index(:orbit_threads, [:owner_id, :updated_at, :id],
             name: :orbit_threads_private_owner_index,
             where: "kind = 'private'"
           )

    execute """
    UPDATE orbit_threads AS thread
    SET title = COALESCE((
      SELECT left(btrim(regexp_replace(message.body, '[[:space:]]+', ' ', 'g')), 200)
      FROM orbit_messages AS message
      WHERE message.thread_id = thread.id AND message.kind = 'human'
        AND btrim(regexp_replace(message.body, '[[:space:]]+', ' ', 'g')) <> ''
      ORDER BY message.position ASC
      LIMIT 1
    ), 'New conversation')
    WHERE thread.kind = 'private' AND thread.title = 'Private thread'
    """

    drop index(:orbit_threads, [:owner_id], name: :orbit_threads_single_private_thread_index)
  end

  def down do
    # Refuse rollback if an owner now has multiple histories. Never delete or merge conversations.
    create unique_index(:orbit_threads, [:owner_id],
             name: :orbit_threads_single_private_thread_index,
             where: "kind = 'private'"
           )

    drop index(:orbit_threads, [:owner_id, :updated_at, :id],
           name: :orbit_threads_private_owner_index
         )

    drop index(:orbit_threads, [:owner_id, :request_id],
           name: :orbit_threads_private_request_index
         )

    alter table(:orbit_threads) do
      remove :request_id
    end
  end
end
