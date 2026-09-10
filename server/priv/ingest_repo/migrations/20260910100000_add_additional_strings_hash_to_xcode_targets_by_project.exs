defmodule Tuist.IngestRepo.Migrations.AddAdditionalStringsHashToXcodeTargetsByProject do
  @moduledoc """
  Keeps the cache configuration, precise compiler identifier, and cache version
  in the project-scoped analytics lookup as a small fingerprint. They are already
  reported in xcode_targets.additional_strings, but were omitted from this lookup.

  Updating the view in place avoids an ingestion gap. Existing rows, and clients
  without these inputs, retain NULL: missing telemetry must not look like a
  compiler change. No full-table rewrite or backfill runs on application startup.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(
    project_id inserted_at command_event_id name product binary_cache_hash binary_cache_hit
    sources_hash resources_hash copy_files_hash core_data_models_hash target_scripts_hash
    environment_hash headers_hash deployment_target_hash info_plist_hash entitlements_hash
    dependencies_hash project_settings_hash target_settings_hash buildable_folders_hash
    additional_hashing_inputs_hash external_hash dependencies
  )

  def up do
    IngestRepo.query!("""
    ALTER TABLE xcode_targets_by_project
    ADD COLUMN IF NOT EXISTS additional_strings_hash Nullable(UInt64) DEFAULT NULL
    """)

    modify_view(
      @columns ++
        [
          "if(empty(additional_strings), NULL, cityHash64(additional_strings)) AS additional_strings_hash"
        ]
    )
  end

  def down do
    modify_view(@columns)

    IngestRepo.query!("""
    ALTER TABLE xcode_targets_by_project DROP COLUMN IF EXISTS additional_strings_hash
    """)
  end

  defp modify_view(columns) do
    IngestRepo.query!("""
    ALTER TABLE xcode_targets_by_project_mv
    MODIFY QUERY SELECT #{Enum.join(columns, ", ")}
    FROM xcode_targets
    WHERE project_id != 0
    """)
  end
end
