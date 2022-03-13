# frozen_string_literal: true

class AddRegionToS3Bucket < ActiveRecord::Migration[7.0]
  def change
    add_column(:s3_buckets, :region, :string)
    change_column_null(:s3_buckets, :region, false, "eu-central-1")
  end
end
