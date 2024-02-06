class AddCacheEventCounts < ActiveRecord::Migration[7.1]
  def change
    change_table(:accounts) do |t|
      t.integer(:cache_upload_event_count, default: 0)
      t.integer(:cache_download_event_count, default: 0)
    end
  end
end
