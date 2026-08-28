defmodule Tuist.IngestRepo.Migrations.AddBuildMetricsToBazelInvocations do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS client_platform LowCardinality(String) DEFAULT 'unknown'"
    )

    execute("ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS cpu_time_ms UInt64 DEFAULT 0")

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS actions_executed UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS targets_loaded UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS targets_configured UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS packages_loaded UInt64 DEFAULT 0"
    )
  end

  def down do
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS packages_loaded")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS targets_configured")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS targets_loaded")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS actions_executed")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS cpu_time_ms")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS client_platform")
  end
end
