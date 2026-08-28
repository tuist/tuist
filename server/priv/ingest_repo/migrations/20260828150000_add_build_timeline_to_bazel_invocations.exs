defmodule Tuist.IngestRepo.Migrations.AddBuildTimelineToBazelInvocations do
  use Ecto.Migration

  def up do
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
  end

  def down do
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
  end
end
