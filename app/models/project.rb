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
  validates :name, exclusion: Environment.blocklisted_slug_keywords

  def full_name
    "#{account.name}/#{name}"
  end

  def remote_cache_storage
    remote_cache_storage_id = self["remote_cache_storage_id"]
    if remote_cache_storage_id.nil?
      DefaultS3Bucket.new
    else
      S3Bucket.find(remote_cache_storage_id)
    end
  end

  def as_json(options = {})
    super(options.merge(only: [:id, :token])).merge({ full_name: full_name })
  end
end

class DefaultS3Bucket
  def name
    case Rails.env
    when "production"
      "tuist-production"
    when "staging"
      "tuist-cloud-staging"
    when "canary"
      "tuist-cloud-canary"
    else
      "tuist-debug"
    end
  end

  def access_key_id
    Environment.aws_access_key_id
  end

  def secret_access_key
    Environment.aws_secret_access_key
  end

  def region
    Environment.aws_region
  end

  def account_id
    nil
  end

  def iv
    nil
  end
end
