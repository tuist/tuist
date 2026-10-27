defmodule Tuist.Repo.Migrations.AddDashboardLanguageToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :preferred_locale, :string, null: true
    end
  end
end
