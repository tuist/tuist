defmodule Tuist.IngestRepo.Migrations.AddFunctionNameToTestRunEnumeratedTests do
  @moduledoc """
  The function of an enumerated test whose results report it under a display
  name (Swift Testing's `@Test("…")`). `xcodebuild -enumerate-tests` lists the
  function and the result bundle the display name, so a run that skipped such
  a test would name it differently from every run that executed it; this is
  what lets the server give it the display name an earlier run recorded.

  The lookup is by function name within the project, which the sort key does
  not reach, so a bloom filter lets it skip the granules (nearly all: only
  tests declared with a display name have a function) holding none of them.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute(
      "ALTER TABLE test_run_enumerated_tests ADD COLUMN IF NOT EXISTS function_name String DEFAULT '' AFTER name"
    )

    execute(
      "ALTER TABLE test_run_enumerated_tests ADD INDEX IF NOT EXISTS idx_function_name function_name TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    execute("ALTER TABLE test_run_enumerated_tests DROP INDEX IF EXISTS idx_function_name")
    execute("ALTER TABLE test_run_enumerated_tests DROP COLUMN IF EXISTS function_name")
  end
end
