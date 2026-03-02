defmodule Tuist.Repo.Migrations.ChangeAutoQuarantineFlakyTestsDefaultToFalse do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :auto_quarantine_flaky_tests, :boolean,
        default: false,
        from: {:boolean, default: true}
    end
  end
end
