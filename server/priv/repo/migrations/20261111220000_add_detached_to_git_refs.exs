defmodule Tuist.Repo.Migrations.AddDetachedToGitRefs do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # A detached ref holds a listed commit no branch or pull request owns, so
  # its file changes have a place (`Tuist.GitHistory.detach/3`). Refs are
  # looked up by the ref they fork from when one is rewritten or written
  # below, and there is now one per such commit.
  def change do
    alter table(:git_refs) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :detached, :boolean, null: false, default: false
    end

    create index(:git_refs, [:parent_ref_id],
             where: "parent_ref_id IS NOT NULL",
             concurrently: true
           )
  end
end
