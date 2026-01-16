defmodule Tuist.Repo.Migrations.AddTestCaseFieldsToFlakyTestAlerts do
  use Ecto.Migration

  def change do
    alter table(:flaky_test_alerts) do
      add :test_case_id, :uuid
      add :test_case_name, :string
      add :test_case_module_name, :string
      add :test_case_suite_name, :string
    end
  end
end
