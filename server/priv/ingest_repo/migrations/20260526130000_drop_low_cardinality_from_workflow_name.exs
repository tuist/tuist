defmodule Tuist.IngestRepo.Migrations.DropLowCardinalityFromWorkflowName do
  use Ecto.Migration

  # `workflow_name` is whatever the customer types in the `name:`
  # field at the top of their workflow file. That's per-account
  # free-form input — a workspace with N microservices each named
  # after a feature ships easily a few hundred distinct values, and
  # the table is global. Once the per-part dictionary outgrows the
  # ~10K-distinct-values sweet spot, LowCardinality becomes negative:
  # the dictionary blocks bloat, and reads pay extra indirection
  # without compression upside. Plain String is the right fit.
  #
  # `fleet_name`, `status`, and `conclusion` stay LowCardinality —
  # those are bounded sets (per-account pools, four lifecycle
  # states, four conclusion values).
  def up do
    execute("ALTER TABLE runner_jobs MODIFY COLUMN workflow_name String DEFAULT ''")
  end

  def down do
    execute("ALTER TABLE runner_jobs MODIFY COLUMN workflow_name LowCardinality(String) DEFAULT ''")
  end
end
