defmodule Tuist.Repo.Migrations.DropFlakyTestAlertTables do
  use Ecto.Migration

  def change do
    # Drop flaky_test_alerts first as it has a foreign key to flaky_test_alert_rules
    drop table(:flaky_test_alerts)
    drop table(:flaky_test_alert_rules)
  end
end
