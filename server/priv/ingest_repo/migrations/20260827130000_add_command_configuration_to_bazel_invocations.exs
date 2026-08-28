defmodule Tuist.IngestRepo.Migrations.AddCommandConfigurationToBazelInvocations do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS bazel_version LowCardinality(String) DEFAULT ''"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS configurations Array(String) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS compilation_mode LowCardinality(String) DEFAULT ''"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS remote_cache_enabled Bool DEFAULT false"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS remote_execution_enabled Bool DEFAULT false"
    )
  end

  def down do
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS remote_execution_enabled")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS remote_cache_enabled")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS compilation_mode")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS configurations")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS bazel_version")
  end
end
