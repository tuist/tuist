defmodule Atlas.Repo.Migrations.AddOrbitToolMessageParent do
  use Ecto.Migration

  def change do
    create unique_index(:orbit_messages, [:id, :thread_id, :run_id])

    alter table(:orbit_messages) do
      add :parent_message_id,
          references(:orbit_messages,
            type: :uuid,
            with: [thread_id: :thread_id, run_id: :run_id],
            on_delete: :delete_all
          )
    end

    create index(:orbit_messages, [:parent_message_id])

    create constraint(:orbit_messages, :orbit_messages_internal_child,
             check:
               "parent_message_id IS NULL OR (kind = 'tool' AND author_id IS NULL AND run_id IS NOT NULL AND parent_message_id <> id)"
           )
  end
end
