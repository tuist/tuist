defmodule Tuist.IngestRepo.Migrations.MakeGradleStringColumnsNonNullable do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN gradle_version String DEFAULT '' SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN java_version String DEFAULT '' SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN git_branch String DEFAULT '' SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN git_commit_sha String DEFAULT '' SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN git_ref String DEFAULT '' SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN root_project_name String DEFAULT '' SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_tasks MODIFY COLUMN task_type String DEFAULT '' SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_tasks MODIFY COLUMN cache_key String DEFAULT '' SETTINGS mutations_sync = 1"
    )
  end

  def down do
    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN gradle_version Nullable(String) SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN java_version Nullable(String) SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN git_branch Nullable(String) SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN git_commit_sha Nullable(String) SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN git_ref Nullable(String) SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_builds MODIFY COLUMN root_project_name Nullable(String) SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_tasks MODIFY COLUMN task_type Nullable(String) SETTINGS mutations_sync = 1"
    )

    execute(
      "ALTER TABLE gradle_tasks MODIFY COLUMN cache_key Nullable(String) SETTINGS mutations_sync = 1"
    )
  end
end
