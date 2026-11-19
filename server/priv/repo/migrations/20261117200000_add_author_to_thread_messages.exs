defmodule Tuist.Repo.Migrations.AddAuthorToThreadMessages do
  use Ecto.Migration

  # The concurrent index cannot be built inside a transaction.
  @disable_ddl_transaction true
  @disable_migration_lock true

  # The person who wrote a human message. A run acts for its message's author:
  # their MCP servers and their app's tools. Earlier messages stay NULL and
  # are treated as the thread owner's.
  def change do
    alter table(:thread_messages) do
      # Every existing row is NULL, so there is nothing for validation to scan;
      # new rows are still checked.
      add :author_id, references(:users, on_delete: :nilify_all, validate: false)
    end

    # Deleting a user nilifies their authored messages through this index.
    create index(:thread_messages, [:author_id], concurrently: true)
  end
end
