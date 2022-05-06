# frozen_string_literal: true

class AddCacheWarmMetadataCommandEventsTable < ActiveRecord::Migration[7.0]
  def change
    create_table(:cache_warm_metadata_command_events) do |t|
      t.string(:cacheable_targets)
      t.string(:local_cache_target_hits)
      t.string(:remote_cache_target_hits)
    end

    change_table(:command_events) do |t|
      t.references(:metadata, polymorphic: true, null: true)
    end
  end
end
