defmodule Tuist.IngestRepo.Migrations.AddTargetPatternsToBazelInvocations do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS target_patterns Array(String) DEFAULT []"
    )
  end

  def down do
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS target_patterns")
  end
end
