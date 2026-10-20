defmodule Tuist.Repo.Migrations.IndexLiveGitlabAssignments do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:runner_gitlab_jobs, [:inserted_at],
             where: "payload IS NOT NULL",
             name: :runner_gitlab_jobs_live_inserted_at_index,
             concurrently: true
           )

    create index(:runner_gitlab_jobs, [:connection_id],
             where: "payload IS NOT NULL",
             name: :runner_gitlab_jobs_live_connection_id_index,
             concurrently: true
           )
  end
end
