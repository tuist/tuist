defmodule Tuist.Repo.Migrations.RouteGitlabJobsByTags do
  use Ecto.Migration

  def change do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop unique_index(:runner_gitlab_connections, [:account_id, :profile_label])

    alter table(:runner_gitlab_connections) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :profile_label, :string
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_gitlab_connections, [:account_id, :url])

    alter table(:runner_gitlab_jobs) do
      add :routing_error, :string
    end
  end
end
