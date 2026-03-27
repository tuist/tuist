defmodule Tuist.Repo.Migrations.AddFlakyAutoClearDaysToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :flaky_cooldown_days, :integer, default: 14, null: false
    end
  end
end
