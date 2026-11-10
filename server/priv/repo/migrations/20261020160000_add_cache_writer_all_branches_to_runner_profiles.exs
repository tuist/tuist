defmodule Tuist.Repo.Migrations.AddCacheWriterAllBranchesToRunnerProfiles do
  use Ecto.Migration

  def up do
    alter table(:runner_profiles) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :cache_writer_all_branches, :boolean, null: false, default: true
    end

    flush()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(customized_statement())
  end

  def down do
    alter table(:runner_profiles) do
      # Rolling back only drops the column this migration added.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :cache_writer_all_branches
    end
  end

  # Profiles whose saving branches were customized keep exactly that policy.
  def customized_statement do
    """
    UPDATE runner_profiles
       SET cache_writer_all_branches = false
     WHERE cache_writer_branches IS NOT NULL OR NOT cache_writer_default_branch
    """
  end
end
