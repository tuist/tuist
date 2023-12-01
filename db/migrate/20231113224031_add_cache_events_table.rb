class AddCacheEventsTable < ActiveRecord::Migration[7.1]
  def change
    create_table(:cache_events) do |t|
      t.string(:name, null: false)
      t.integer(:event_type, null: false)
      t.integer(:size, null: false)
      t.references(:project, null: false)
      t.timestamps
    end
  end
end
