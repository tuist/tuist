defmodule Tuist.Repo.Migrations.AddDashboardLanguageToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :dashboard_language, :string, null: true
    end
  end
end
