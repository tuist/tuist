defmodule Atlas.Repo.Migrations.AddAccountOverviewSummary do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :overview_summary, :text
      add :overview_summary_generated_at, :utc_datetime
    end
  end
end
