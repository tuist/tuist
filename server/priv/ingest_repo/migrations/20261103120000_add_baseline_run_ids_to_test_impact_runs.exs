defmodule Tuist.IngestRepo.Migrations.AddBaselineRunIdsToTestImpactRuns do
  use Ecto.Migration

  # The baseline's runs an impact run read its tests in scope from. A shard
  # read derives its skip list from them (those tests less the selected ones),
  # so every shard sees the tests the decision saw, even when the baseline
  # commit gets another run later. Empty on fallbacks.
  def change do
    alter table(:test_impact_runs) do
      add :baseline_run_ids, :"Array(UUID)"
    end
  end
end
