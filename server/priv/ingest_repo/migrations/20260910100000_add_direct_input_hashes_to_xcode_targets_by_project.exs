defmodule Tuist.IngestRepo.Migrations.AddDirectInputHashesToXcodeTargetsByProject do
  @moduledoc """
  Projects optional reported hash inputs as a map of fingerprints. Only inputs
  known on both observations are compared, so gaining telemetry cannot invent
  a change or hide changes to another input already reported by older clients.

  Missing historical inputs remain absent. Updating the view in place avoids
  an ingestion gap and does not backfill or rewrite retained rows on startup.
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
    ADD COLUMN IF NOT EXISTS direct_inputs_hashes Map(String, Nullable(UInt64)) DEFAULT map()
    """)

    modify_view(
      @columns ++
        [
          """
          mapFilter((input, hash) -> isNotNull(hash), map(
            'additional_strings', if(empty(additional_strings), NULL, cityHash64(additional_strings)),
            'destinations', if(
              notEmpty(hashed_destinations) OR (
                isNotNull(embedded_product_references_hash) AND isNotNull(foreign_build_hash)
                AND isNotNull(test_device) AND isNotNull(test_runtime)
              ), cityHash64(hashed_destinations), NULL
            ),
            'embedded_product_references', cityHash64(embedded_product_references_hash),
            'foreign_build', cityHash64(foreign_build_hash),
            'test_device', cityHash64(test_device),
            'test_runtime', cityHash64(test_runtime)
          )) AS direct_inputs_hashes
          """
        ]
    )
  end

  def down do
    modify_view(@columns)

    IngestRepo.query!("""
    ALTER TABLE xcode_targets_by_project DROP COLUMN IF EXISTS direct_inputs_hashes
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
