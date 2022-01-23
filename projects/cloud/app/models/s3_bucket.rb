# frozen_string_literal: true

class S3Bucket < ApplicationRecord
  # Associations
  has_many :projects, as: :remote_cache_storage
end
