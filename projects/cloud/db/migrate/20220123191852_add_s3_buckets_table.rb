# frozen_string_literal: true

class AddS3BucketsTable < ActiveRecord::Migration[7.0]
  def change
    create_table(:s3_buckets) do |t|
      t.string(:name, null: false)
      t.string(:access_key_id, null: false)
      t.string(:secret_access_key, null: true)
      t.string(:iv, null: true)
      t.timestamps(null: false)
    end

    add_reference(:projects, :remote_cache_storage, polymorphic: true, null: true)
    add_reference(:s3_buckets, :account, foreign_key: true, null: false)
    add_index(:s3_buckets, [:name, :account_id], unique: true)
  end
end
