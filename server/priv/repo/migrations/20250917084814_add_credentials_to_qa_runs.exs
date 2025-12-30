defmodule Tuist.Repo.Migrations.AddCredentialsToQaRuns do
  use Ecto.Migration

  def change do
    alter table(:qa_runs) do
      add :email, :text, default: "", null: false
      add :password, :text, default: "", null: false
    end
  end
end
