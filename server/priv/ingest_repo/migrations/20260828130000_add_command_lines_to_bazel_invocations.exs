defmodule Tuist.IngestRepo.Migrations.AddCommandLinesToBazelInvocations do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS requested_command String DEFAULT ''"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS original_command_line Array(String) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS canonical_command_line Array(String) DEFAULT []"
    )
  end

  def down do
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS canonical_command_line")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS original_command_line")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS requested_command")
  end
end
