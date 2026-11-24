defmodule Tuist.Repo.Migrations.AddAttachmentsToThreadMessages do
  use Ecto.Migration

  # Inline bytes follow the message's authorization and retention.
  def change do
    alter table(:thread_messages) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :attachments, {:array, :map}, null: false, default: []
    end
  end
end
