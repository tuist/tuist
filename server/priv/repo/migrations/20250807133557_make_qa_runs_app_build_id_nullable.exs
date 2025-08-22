defmodule Tuist.Repo.Migrations.MakeQARunsAppBuildIdNullable do
  use Ecto.Migration

  def up do
    drop constraint(:qa_runs, "qa_runs_app_build_id_fkey")

    alter table(:qa_runs) do
      modify :app_build_id, references(:app_builds, type: :uuid, on_delete: :delete_all),
        null: true
    end
  end

  def down do
    drop constraint(:qa_runs, "qa_runs_app_build_id_fkey")

    alter table(:qa_runs) do
      modify :app_build_id, references(:app_builds, type: :uuid, on_delete: :delete_all),
        null: false
    end
  end
end
