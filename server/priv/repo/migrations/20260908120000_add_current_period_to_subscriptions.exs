defmodule Tuist.Repo.Migrations.AddCurrentPeriodToSubscriptions do
  use Ecto.Migration

  def up do
    alter table(:subscriptions) do
      add :current_period_start, :timestamptz
      add :current_period_end, :timestamptz
    end
  end

  def down do
    alter table(:subscriptions) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :current_period_start
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :current_period_end
    end
  end
end
