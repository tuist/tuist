# frozen_string_literal: true

class AddCacheMetadataToCommandEvent < ActiveRecord::Migration[7.0]
  def change
    change_table(:command_events) do |t|
      t.string(:cacheable_targets)
      t.string(:local_cache_target_hits)
      t.string(:remote_cache_target_hits)
    end
  end
end
