# frozen_string_literal: true

class CacheService < ApplicationService
  module Error
    class S3ObjectNotFound < StandardError
      attr_reader :bucket_name, :object_key

      def initialize(bucket_name, object_key)
        @bucket_name = bucket_name
        @object_key = object_key
      end

      def message
        "Object with a key #{object_key} was not found in the #{bucket_name} S3 bucket."
      end

      def http_status
        404
      end
    end
  end

  attr_reader :account_name, :project_name, :hash, :name, :user, :object_key

  def initialize(project_slug:, hash:, name:, user:)
    super()
    split_project_slug = project_slug.split("/")
    @account_name = split_project_slug.first
    @project_name = split_project_slug.last
    @project_slug = project_slug
    @hash = hash
    @object_key = "#{hash}/#{name}"
    @name = name
    @user = user
  end

  def object_exists?
    project = ProjectFetchService.call(
      name: project_name,
      account_name: account_name,
      user: user
    )
    s3_client = s3_client(s3_bucket: project.remote_cache_storage)
    begin
      s3_client.head_object(
        bucket: project.remote_cache_storage.name,
        key: object_key,
      )
      true
    rescue Aws::S3::Errors::NotFound
      false
    end
  end

  def fetch
    project = ProjectFetchService.call(
      name: project_name,
      account_name: account_name,
      user: user
    )
    s3_client = s3_client(s3_bucket: project.remote_cache_storage)
    signer = Aws::S3::Presigner.new(client: s3_client)
    url = signer.presigned_url(
      :get_object,
      bucket: project.remote_cache_storage.name,
      key: object_key
    )
    url
  end

  def upload
    project = ProjectFetchService.call(
      name: project_name,
      account_name: account_name,
      user: user
    )
    s3_client = s3_client(s3_bucket: project.remote_cache_storage)
    s3_client.put_object(
      bucket: project.remote_cache_storage.name,
      key: object_key
    )
    signer = Aws::S3::Presigner.new(client: s3_client)
    url = signer.presigned_url(
      :put_object,
      bucket: project.remote_cache_storage.name,
      key: object_key
    )
    url
  end

  def verify_upload
    project = ProjectFetchService.call(
      name: project_name,
      account_name: account_name,
      user: user
    )
    s3_client = s3_client(s3_bucket: project.remote_cache_storage)
    object = s3_client.get_object(
      bucket: project.remote_cache_storage.name,
      key: object_key
    )
    object.content_length
  end

  private
    def s3_client(s3_bucket:)
      secret_access_key = DecipherService.call(
        key: Base64.decode64(s3_bucket.secret_access_key),
        iv: Base64.decode64(s3_bucket.iv)
      )
      Aws::S3::Client.new(
        # TODO: Add this to database and make it configurable
        region: "eu-central-1",
        access_key_id: s3_bucket.access_key_id,
        secret_access_key: secret_access_key,
      )
    end
end
