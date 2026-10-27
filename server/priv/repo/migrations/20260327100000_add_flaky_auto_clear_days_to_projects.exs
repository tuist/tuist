defmodule Tuist.Repo.Migrations.AddFlakyAutoClearDaysToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :flaky_cooldown_days, :integer, default: 14, null: false
    end
  end
end
