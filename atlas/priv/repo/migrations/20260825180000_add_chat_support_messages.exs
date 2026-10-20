defmodule Atlas.Repo.Migrations.AddChatSupportMessages do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE support_messages
    ADD CONSTRAINT support_messages_kind_check_with_chat
    CHECK (kind IN ('inbound', 'chat', 'outbound', 'note')) NOT VALID
    """)

    execute(
      "ALTER TABLE support_messages VALIDATE CONSTRAINT support_messages_kind_check_with_chat"
    )

    execute("ALTER TABLE support_messages DROP CONSTRAINT support_messages_kind_check")

    execute("""
    ALTER TABLE support_messages
    RENAME CONSTRAINT support_messages_kind_check_with_chat TO support_messages_kind_check
    """)
  end

  def down do
    raise "Cannot safely roll back after support chat messages have been created."
  end
end
