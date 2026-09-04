defmodule Tuist.IngestRepo.Migrations.AddGradleCacheDiagnostics do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE gradle_builds ADD COLUMN IF NOT EXISTS configuration_cache_status LowCardinality(String) DEFAULT ''"
    )

    execute(
      "ALTER TABLE gradle_builds ADD COLUMN IF NOT EXISTS configuration_cache_entry_size Nullable(Int64)"
    )

    execute(
      "ALTER TABLE gradle_builds ADD COLUMN IF NOT EXISTS configuration_cache_load_duration_ms Nullable(UInt64)"
    )

    execute(
      "ALTER TABLE gradle_builds ADD COLUMN IF NOT EXISTS configuration_cache_invalidation_reasons Array(String) DEFAULT []"
    )

    execute(
      "ALTER TABLE gradle_tasks ADD COLUMN IF NOT EXISTS remote_cache_miss Bool DEFAULT false"
    )

    execute(
      "ALTER TABLE gradle_tasks ADD COLUMN IF NOT EXISTS remote_cache_stored Nullable(Bool)"
    )

    create table(:gradle_configuration_operations,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (gradle_build_id, started_at, inserted_at) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :gradle_build_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :phase, :"LowCardinality(String)", null: false
      add :build_path, :string, null: false
      add :project_path, :string, null: false, default: ""
      add :duration_ms, :UInt64, null: false
      add :started_at, :"DateTime64(6)", null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create table(:gradle_artifact_transforms,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (gradle_build_id, started_at, inserted_at) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :gradle_build_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :transformer_name, :string, null: false
      add :transform_action_class, :string, null: false
      add :subject_name, :string, null: false
      add :artifact_name, :string, null: false
      add :consumer_project_path, :string, null: false, default: ""
      add :duration_ms, :UInt64, null: false
      add :started_at, :"DateTime64(6)", null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end

  def down do
    drop table(:gradle_artifact_transforms)
    drop table(:gradle_configuration_operations)
    execute("ALTER TABLE gradle_tasks DROP COLUMN IF EXISTS remote_cache_stored")
    execute("ALTER TABLE gradle_tasks DROP COLUMN IF EXISTS remote_cache_miss")

    execute(
      "ALTER TABLE gradle_builds DROP COLUMN IF EXISTS configuration_cache_invalidation_reasons"
    )

    execute(
      "ALTER TABLE gradle_builds DROP COLUMN IF EXISTS configuration_cache_load_duration_ms"
    )

    execute("ALTER TABLE gradle_builds DROP COLUMN IF EXISTS configuration_cache_entry_size")
    execute("ALTER TABLE gradle_builds DROP COLUMN IF EXISTS configuration_cache_status")
  end
end
