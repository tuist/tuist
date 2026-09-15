defmodule Tuist.IngestRepo.Migrations.AddCustomMetadataToBazelInvocations do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS custom_values Map(String, String) DEFAULT map()"
    )
  end

  def down do
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS custom_values")
  end
end
