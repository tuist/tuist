defmodule Atlas.Repo.Migrations.AddSummaryToSpecRevisions do
  use Ecto.Migration

  def change do
    alter table(:spec_revisions) do
      add :summary, :text
    end
  end
end
