defmodule Tuist.IngestRepo.Migrations.AddGitMetadataToBazelInvocations do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS git_branch String DEFAULT ''")

    execute(
      "ALTER TABLE bazel_invocations ADD COLUMN IF NOT EXISTS git_commit_sha String DEFAULT ''"
    )
  end

  def down do
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS git_commit_sha")
    execute("ALTER TABLE bazel_invocations DROP COLUMN IF EXISTS git_branch")
  end
end
