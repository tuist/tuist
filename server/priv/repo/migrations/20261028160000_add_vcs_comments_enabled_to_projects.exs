defmodule Tuist.Repo.Migrations.AddVcsCommentsEnabledToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # Preserve commenting for existing integrations and enable it for new ones.
      # PostgreSQL 11+ adds constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :vcs_comments_enabled, :boolean, default: true, null: false
    end
  end
end
