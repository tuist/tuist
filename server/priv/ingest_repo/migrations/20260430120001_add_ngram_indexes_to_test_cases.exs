defmodule Tuist.IngestRepo.Migrations.AddNgramIndexesToTestCases do
  @moduledoc """
  Adds n-gram bloom-filter indexes to `test_cases` so the ILIKE searches issued
  by the Test Cases / Flaky / Quarantined listing pages can skip granules
  instead of scanning the whole partition.

  The table is `ORDER BY (project_id, module_name, suite_name, name, id)`, so
  `project_id` is binary-searchable but `ILIKE '%term%'` on `name`,
  `module_name`, or `suite_name` falls back to a full scan within the project
  (production traces showed 100–200 M rows scanned to return < 20 matches).

  `ngrambf_v1(3, …)` stores 3-grams of each value into a bloom filter per
  granule; ClickHouse uses it to prune granules where no 3-gram from the
  search term can exist. The granule scan happens after the prune, so this
  doesn't change result correctness — only how many granules are read.

  Idempotent so partial migrations on ClickHouse Cloud (DDL is non-
  transactional) can be re-run safely.
  """
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE test_cases ADD INDEX IF NOT EXISTS idx_name_ngram name TYPE ngrambf_v1(3, 65536, 3, 0) GRANULARITY 4"
    )

    execute(
      "ALTER TABLE test_cases ADD INDEX IF NOT EXISTS idx_module_name_ngram module_name TYPE ngrambf_v1(3, 65536, 3, 0) GRANULARITY 4"
    )

    execute(
      "ALTER TABLE test_cases ADD INDEX IF NOT EXISTS idx_suite_name_ngram suite_name TYPE ngrambf_v1(3, 65536, 3, 0) GRANULARITY 4"
    )

    execute("ALTER TABLE test_cases MATERIALIZE INDEX idx_name_ngram")
    execute("ALTER TABLE test_cases MATERIALIZE INDEX idx_module_name_ngram")
    execute("ALTER TABLE test_cases MATERIALIZE INDEX idx_suite_name_ngram")
  end

  def down do
    execute("ALTER TABLE test_cases DROP INDEX IF EXISTS idx_name_ngram")
    execute("ALTER TABLE test_cases DROP INDEX IF EXISTS idx_module_name_ngram")
    execute("ALTER TABLE test_cases DROP INDEX IF EXISTS idx_suite_name_ngram")
  end
end
