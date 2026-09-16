defmodule Tuist.Repo.Migrations.AddCoverageGatesToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :coverage_gates_enabled, :boolean, null: false, default: false
      add :coverage_gate_min_patch_coverage, :float
      add :coverage_gate_max_total_drop, :float
      add :coverage_patch_partial_runs, :boolean, null: false, default: false
    end
  end
end
