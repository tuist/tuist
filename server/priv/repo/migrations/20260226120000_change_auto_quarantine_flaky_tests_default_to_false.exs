defmodule Tuist.Repo.Migrations.ChangeAutoQuarantineFlakyTestsDefaultToFalse do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      modify :auto_quarantine_flaky_tests, :boolean, default: false, from: {:boolean, default: true}
    end
  end
end
