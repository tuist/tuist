defmodule Tuist.Repo.Migrations.AddCoverageGatesToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :coverage_gates_enabled, :boolean, null: false, default: false
      add :coverage_gate_min_patch_coverage, :float
      add :coverage_gate_max_total_drop, :float
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
    end
  end
end
