defmodule Tuist.Repo.Migrations.MakeQARunsAppBuildIdNullable do
  use Ecto.Migration

  def change do
    drop constraint(:qa_runs, "qa_runs_app_build_id_fkey")

    alter table(:qa_runs) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :app_build_id, references(:app_builds, type: :uuid, on_delete: :delete_all),
        null: true
    end
  end
end
