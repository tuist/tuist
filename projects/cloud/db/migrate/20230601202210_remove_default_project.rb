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

    # s3_bucket = S3BucketCreateService.call(
    #   name: "tuist",
    #   access_key_id: Rails.application.credentials.aws[:access_key_id],
    #   secret_access_key: Rails.application.credentials.aws[:secret_access_key],
    #   region: "eu-west-1",
    #   account_id: nil,
    # )
    # project.update(remote_cache_storage: s3_bucket)

    # TODO: We should add instructions on how to create a bucket manually for self-hosted sollutions
    # s3_client.create_bucket(bucket: )
  end
end
