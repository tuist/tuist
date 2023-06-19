# frozen_string_literal: true

class Project < ApplicationRecord
  include TokenAuthenticatable

  # Token authenticatable
  autogenerates_token :token

  # Associations
  has_many :command_events, dependent: :destroy
  has_many :users, foreign_key: :last_visited_project_id, dependent: :nullify
  belongs_to :account, optional: false
  belongs_to :remote_cache_storage, polymorphic: true, optional: true

  # Validations
  validates :name, exclusion: Defaults.fetch(:blocklisted_slug_keywords)

  def remote_cache_storage
    remote_cache_storage_id = self["remote_cache_storage_id"]
    if remote_cache_storage_id.nil?
      DefaultS3Bucket.new
    else
      S3Bucket.find(remote_cache_storage_id)
    end
  end
end

class DefaultS3Bucket
  def name
    if Rails.env.production?
      "tuist"
    else
      "tuist-debug"
    end
  end

  def access_key_id
    Rails.application.credentials.aws[:access_key_id]
  end

  def secret_access_key
    Rails.application.credentials.aws[:secret_access_key]
  end

  def region
    "eu-west-1"
  end

  def account_id
    nil
  end

  def iv
    nil
  end
end
