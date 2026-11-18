defmodule Tuist.IngestRepo.Migrations.AddTestImpactRunIdToShardPlans do
  use Ecto.Migration

  # The impact run a coverage plan distributes (`test_impact_runs`). Its suites
  # stay in `shard_plan_test_suites` and their selected tests in
  # `test_impact_run_tests`, so nothing is stored twice. Null for every other
  # plan.
  def change do
    alter table(:shard_plans) do
      add :test_impact_run_id, :"Nullable(UUID)"
    end
  end
end
