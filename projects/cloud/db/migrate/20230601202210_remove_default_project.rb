# frozen_string_literal: true

class RemoveDefaultProject < ActiveRecord::Migration[7.0]
  def change
    S3Bucket.where(is_default: true).pluck(:default_project_id)
      .filter { |id| id != nil }
      .map { |id| Project.where(id: id) }
      .each { |project| project.update(remote_cache_storage: nil) }
    S3Bucket.where(is_default: true).delete_all
    remove_reference(:s3_buckets, :default_project, index: true, foreign_key: false)
    remove_column(:s3_buckets, :is_default)
  end
end
