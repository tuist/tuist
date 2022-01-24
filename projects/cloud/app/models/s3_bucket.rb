# frozen_string_literal: true

class S3Bucket < ApplicationRecord
  self.table_name = "s3_buckets"
  # Associations
  belongs_to :account, optional: false
  has_many :projects, as: :remote_cache_storage
end
