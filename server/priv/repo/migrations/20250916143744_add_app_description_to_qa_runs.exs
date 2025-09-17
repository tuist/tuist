defmodule Tuist.Repo.Migrations.AddAppDescriptionToQaRuns do
  use Ecto.Migration

  def change do
    alter table(:qa_runs) do
      add :app_description, :text, default: "", null: false
    end
  end
end
