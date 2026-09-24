defmodule Tuist.IngestRepo.Migrations.AddFunctionNameToTestRunEnumeratedTests do
  @moduledoc """
  The function of an enumerated test whose results report it under a display
  name (Swift Testing's `@Test("…")`). `xcodebuild -enumerate-tests` lists the
  function and the result bundle the display name, so a run that skipped such
  a test would name it differently from every run that executed it; this is
  what lets the server give it the display name an earlier run recorded.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute(
      "ALTER TABLE test_run_enumerated_tests ADD COLUMN IF NOT EXISTS function_name String DEFAULT '' AFTER name"
    )
  end

  def down do
    execute("ALTER TABLE test_run_enumerated_tests DROP COLUMN IF EXISTS function_name")
  end
end
