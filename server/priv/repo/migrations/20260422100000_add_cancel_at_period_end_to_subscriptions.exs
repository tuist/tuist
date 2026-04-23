defmodule Tuist.Repo.Migrations.AddCancelAtPeriodEndToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :cancel_at_period_end, :boolean, default: false, null: false
    end
  end
end
