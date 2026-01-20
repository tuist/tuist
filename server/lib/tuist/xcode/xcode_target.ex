defmodule Tuist.Xcode.XcodeTarget do
  @moduledoc false
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false

  @derive {
    Flop.Schema,
    filterable: [:name, :binary_cache_hit],
    sortable: [:name, :binary_cache_hit, :selective_testing_hit],
    default_order: %{
      order_by: [:name],
      order_directions: [:asc]
    }
  }
  schema "xcode_targets" do
    field :id, :string
    field :name, :string
    field :binary_cache_hash, Ch, type: "Nullable(String)"
    field :binary_cache_hit, Ch, type: "Enum8('miss' = 0, 'local' = 1, 'remote' = 2)"
    field :binary_build_duration, Ch, type: "Nullable(UInt32)"
    field :selective_testing_hash, Ch, type: "Nullable(String)"
    field :selective_testing_hit, Ch, type: "Enum8('miss' = 0, 'local' = 1, 'remote' = 2)"
    field :xcode_project_id, Ch, type: "UUID"
    field :command_event_id, Ch, type: "UUID"
    field :product, Ch, type: "LowCardinality(String)", default: ""
    field :bundle_id, Ch, type: "String", default: ""
    field :product_name, Ch, type: "String", default: ""

    # Subhashes
    field :sources_hash, Ch, type: "String", default: ""
    field :resources_hash, Ch, type: "String", default: ""
    field :copy_files_hash, Ch, type: "String", default: ""
    field :core_data_models_hash, Ch, type: "String", default: ""
    field :target_scripts_hash, Ch, type: "String", default: ""
    field :environment_hash, Ch, type: "String", default: ""
    field :headers_hash, Ch, type: "String", default: ""
    field :deployment_target_hash, Ch, type: "String", default: ""
    field :info_plist_hash, Ch, type: "String", default: ""
    field :entitlements_hash, Ch, type: "String", default: ""
    field :dependencies_hash, Ch, type: "String", default: ""
    field :project_settings_hash, Ch, type: "String", default: ""
    field :target_settings_hash, Ch, type: "String", default: ""
    field :buildable_folders_hash, Ch, type: "String", default: ""
    field :destinations, Ch, type: "Array(LowCardinality(String))", default: []
    field :additional_strings, Ch, type: "Array(String)", default: []
    field :external_hash, Ch, type: "String", default: ""

    belongs_to :command_event, Tuist.CommandEvents.Event,
      foreign_key: :command_event_id,
      references: :id,
      define_field: false

    belongs_to :xcode_project, Tuist.Xcode.XcodeProject,
      foreign_key: :xcode_project_id,
      references: :id,
      define_field: false

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end

  def changeset(command_event_id, xcode_project_id, xcode_target, inserted_at \\ nil) do
    binary_cache_metadata = xcode_target["binary_cache_metadata"]
    selective_testing_metadata = xcode_target["selective_testing_metadata"]
    subhashes = (binary_cache_metadata || %{})["subhashes"] || %{}

    %{
      id: UUIDv7.generate(),
      name: xcode_target["name"],
      command_event_id: command_event_id,
      xcode_project_id: xcode_project_id,
      binary_cache_hash: binary_cache_metadata["hash"],
      binary_cache_hit: hit_enum_to_int(hit_value_to_enum(binary_cache_metadata["hit"], :miss)),
      binary_build_duration: binary_cache_metadata["build_duration"],
      selective_testing_hash: selective_testing_metadata["hash"],
      selective_testing_hit: hit_enum_to_int(hit_value_to_enum(selective_testing_metadata["hit"], :miss)),
      product: xcode_target["product"],
      bundle_id: xcode_target["bundle_id"],
      product_name: xcode_target["product_name"],
      sources_hash: subhashes["sources"],
      resources_hash: subhashes["resources"],
      copy_files_hash: subhashes["copy_files"],
      core_data_models_hash: subhashes["core_data_models"],
      target_scripts_hash: subhashes["target_scripts"],
      environment_hash: subhashes["environment"],
      headers_hash: subhashes["headers"],
      deployment_target_hash: subhashes["deployment_target"],
      info_plist_hash: subhashes["info_plist"],
      entitlements_hash: subhashes["entitlements"],
      dependencies_hash: subhashes["dependencies"],
      project_settings_hash: subhashes["project_settings"],
      target_settings_hash: subhashes["target_settings"],
      buildable_folders_hash: subhashes["buildable_folders"],
      destinations: xcode_target["destinations"],
      additional_strings: subhashes["additional_strings"],
      external_hash: subhashes["external"],
      inserted_at: inserted_at || NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }
  end

  def normalize_enums(target) do
    %{
      target
      | binary_cache_hit: if(target.binary_cache_hit, do: String.to_atom(target.binary_cache_hit)),
        selective_testing_hit: if(target.selective_testing_hit, do: String.to_atom(target.selective_testing_hit))
    }
  end

  defp hit_value_to_enum(metadata, _default) when is_nil(metadata), do: :miss
  defp hit_value_to_enum(hit_value, _default), do: Tuist.Xcode.normalize_hit_value(hit_value)

  defp hit_enum_to_int(:miss), do: 0
  defp hit_enum_to_int(:local), do: 1
  defp hit_enum_to_int(:remote), do: 2
  defp hit_enum_to_int(_), do: 0
end
