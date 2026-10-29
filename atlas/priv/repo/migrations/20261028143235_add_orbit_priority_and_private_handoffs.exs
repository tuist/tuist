defmodule Atlas.Repo.Migrations.AddOrbitPriorityAndPrivateHandoffs do
  use Ecto.Migration

  def up do
    alter table(:orbit_threads) do
      add :priority, :text
    end

    create constraint(:orbit_threads, :orbit_threads_priority,
             check: "priority IS NULL OR priority IN ('now', 'today', 'later')"
           )

    alter table(:orbit_messages) do
      # Never nilify: deleting a recipient must not turn a private recap public.
      add :recipient_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :private_body, :binary
    end

    drop constraint(:orbit_messages, :orbit_messages_notice_kind)

    create constraint(:orbit_messages, :orbit_messages_notice_kind,
             check:
               "notice_kind IS NULL OR (kind = 'system' AND notice_kind IN ('handoff', 'private_handoff', 'joined'))"
           )

    create constraint(:orbit_messages, :orbit_messages_private_handoff,
             check:
               "(recipient_id IS NULL AND private_body IS NULL AND notice_kind IS DISTINCT FROM 'private_handoff') OR " <>
                 "(recipient_id IS NOT NULL AND private_body IS NOT NULL AND body = '' AND kind = 'system' " <>
                 "AND notice_kind = 'private_handoff' AND NOT address_agent)"
           )
  end

  def down do
    # A rollback must discard private copies, never publish them as shared text.
    execute "DELETE FROM orbit_messages WHERE recipient_id IS NOT NULL"
    execute "UPDATE orbit_messages SET notice_kind = NULL WHERE notice_kind = 'joined'"
    drop constraint(:orbit_messages, :orbit_messages_private_handoff)
    drop constraint(:orbit_messages, :orbit_messages_notice_kind)

    create constraint(:orbit_messages, :orbit_messages_notice_kind,
             check: "notice_kind IS NULL OR (kind = 'system' AND notice_kind = 'handoff')"
           )

    alter table(:orbit_messages) do
      remove :private_body
      remove :recipient_id
    end

    drop constraint(:orbit_threads, :orbit_threads_priority)
    alter table(:orbit_threads), do: remove(:priority)
  end
end
