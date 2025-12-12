defmodule Tuist.IngestRepo.Migrations.AddSubhashesToXcodeTargets do
  use Ecto.Migration

  def change do
    alter table(:xcode_targets) do
      add :product, :"LowCardinality(String)", default: ""
      add :bundle_id, :string, default: ""
      add :product_name, :string, default: ""
      add :destinations, :"Array(LowCardinality(String))", default: fragment("[]")

      # Subhashes
      add :sources_hash, :string, default: ""
      add :resources_hash, :string, default: ""
      add :copy_files_hash, :string, default: ""
      add :core_data_models_hash, :string, default: ""
      add :target_scripts_hash, :string, default: ""
      add :environment_hash, :string, default: ""
      add :headers_hash, :string, default: ""
      add :deployment_target_hash, :string, default: ""
      add :info_plist_hash, :string, default: ""
      add :entitlements_hash, :string, default: ""
      add :dependencies_hash, :string, default: ""
      add :project_settings_hash, :string, default: ""
      add :target_settings_hash, :string, default: ""
      add :buildable_folders_hash, :string, default: ""
      add :additional_strings, :"Array(String)", default: fragment("[]")
      add :external_hash, :string, default: ""
    end
  end
end
