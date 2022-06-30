# frozen_string_literal: true

class AddDefaultRemoteCacheStorage < ActiveRecord::Migration[7.0]
  def change
    add_column(:s3_buckets, :is_default, :boolean, default: false)
  end
end
