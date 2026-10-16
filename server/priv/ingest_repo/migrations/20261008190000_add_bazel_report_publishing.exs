defmodule Tuist.IngestRepo.Migrations.AddBazelReportPublishing do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS submission_auth LowCardinality(String) DEFAULT ''"
    )
  end

  def down do
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS submission_auth")
  end
end
