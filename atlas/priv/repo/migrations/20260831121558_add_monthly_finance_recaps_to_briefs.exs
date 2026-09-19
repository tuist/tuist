defmodule Atlas.Repo.Migrations.AddMonthlyFinanceRecapsToBriefs do
  use Ecto.Migration

  def up do
    alter table(:briefs) do
      add :report, :map, null: false, default: %{}
    end

    drop constraint(:brief_subscriptions, :brief_subscriptions_cadence_check)

    create constraint(:brief_subscriptions, :brief_subscriptions_cadence_check,
             check: "cadence IN ('daily', 'weekly', 'monthly')"
           )

    drop constraint(:briefs, :briefs_cadence_check)

    create constraint(:briefs, :briefs_cadence_check,
             check: "cadence IN ('daily', 'weekly', 'monthly')"
           )
  end

  def down do
    execute("DELETE FROM brief_subscriptions WHERE cadence = 'monthly'")

    drop constraint(:brief_subscriptions, :brief_subscriptions_cadence_check)

    create constraint(:brief_subscriptions, :brief_subscriptions_cadence_check,
             check: "cadence IN ('daily', 'weekly')"
           )

    drop constraint(:briefs, :briefs_cadence_check)

    create constraint(:briefs, :briefs_cadence_check, check: "cadence IN ('daily', 'weekly')")

    alter table(:briefs) do
      remove :report
    end
  end
end
