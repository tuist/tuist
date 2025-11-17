defmodule Tuist.IngestRepo.Migrations.AddTestRunIdIndexToCommandEvents do
  use Ecto.Migration

  def up do
    # Add bloom filter index for test_run_id column
    # Bloom filters are ideal for UUID columns used in equality lookups (test_run_id = 'uuid')
    # High cardinality UUID field, so using GRANULARITY 8 like other UUID columns
    execute(
      "ALTER TABLE command_events ADD INDEX idx_test_run_id test_run_id TYPE bloom_filter GRANULARITY 8"
    )
  end

  def down do
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_test_run_id")
  end
end
