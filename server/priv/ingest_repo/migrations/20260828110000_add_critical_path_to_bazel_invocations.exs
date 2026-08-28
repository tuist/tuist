defmodule Tuist.IngestRepo.Migrations.AddCriticalPathToBazelInvocations do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS critical_path_duration_ms UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS critical_path_action_descriptions Array(String) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS critical_path_action_durations_ms Array(UInt64) DEFAULT []"
    )
  end

  def down do
    execute(
      "ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS critical_path_action_durations_ms"
    )

    execute(
      "ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS critical_path_action_descriptions"
    )

    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS critical_path_duration_ms")
  end
end
