class AddS3BucketTable < ActiveRecord::Migration[7.0]
  def change
    create_table(:s3_buckets) do |t|
      t.string(:bucket_name)
      t.string(:access_key_id)
      t.string(:secret_access_key)
      t.string(:iv)
      t.references(:project, polymorphic: true)
      t.timestamps(null: false)
    end
  end
end
