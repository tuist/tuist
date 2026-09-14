defmodule Tuist.IngestRepo.Migrations.AddBazelInvocationDiagnostics do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS bazel_version LowCardinality(String) DEFAULT ''"
    )

    execute("ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS cpu_time_ms UInt64 DEFAULT 0")

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS actions_created UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS actions_executed UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS targets_configured UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS packages_loaded UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS build_timeline_duration_ms UInt64 DEFAULT 0"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS build_timeline_lanes Array(String) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS build_timeline_span_lanes Array(UInt8) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS build_timeline_span_start_ms Array(UInt64) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS build_timeline_span_durations_ms Array(UInt64) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS build_timeline_span_categories Array(LowCardinality(String)) DEFAULT []"
    )

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS build_timeline_span_descriptions Array(String) DEFAULT []"
    )

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

    execute(
      "ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS build_timeline_span_descriptions"
    )

    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS build_timeline_span_categories")

    execute(
      "ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS build_timeline_span_durations_ms"
    )

    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS build_timeline_span_start_ms")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS build_timeline_span_lanes")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS build_timeline_lanes")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS build_timeline_duration_ms")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS packages_loaded")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS targets_configured")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS actions_executed")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS actions_created")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS cpu_time_ms")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS bazel_version")
  end
end
