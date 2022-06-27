# frozen_string_literal: true

include Rails.application.routes.url_helpers

class CacheService < ApplicationService
  attr_reader :account_name, :project_name, :project_slug, :hash, :name, :user, :object_key, :project

  module Error
    class MissingRemoteCacheStorage < CloudError
      attr_reader :project_slug

      def initialize(project_slug)
        @project_slug = project_slug
      end

      def message
        remote_cache_storage_url = URI.join(root_url, "#{project_slug}/remote-cache")
        """
Project #{project_slug} has no remote cache. \
Define your remote cache at the following url: #{remote_cache_storage_url}.
        """
      end
    end

    class S3BucketForbidden < CloudError
      def message
        "Ensure your secret access key is set correctly, following the instructions here: https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html."
      end
    end
  end

  def initialize(project_slug:, hash:, name:, user:, project:)
    super()
    split_project_slug = project_slug.split("/")
    @account_name = split_project_slug.first
    @project_name = split_project_slug.last
    @project_slug = project_slug
    @hash = hash
    @object_key = "#{hash}/#{name}"
    @name = name
    @user = user
    @project = project
  end

  def object_exists?
    fetch_project_if_necessary
    if project.remote_cache_storage.nil?
      raise Error::MissingRemoteCacheStorage.new(project_slug)
    end
    s3_client = s3_client(s3_bucket: project.remote_cache_storage)
    begin
      s3_client.head_object(
        bucket: project.remote_cache_storage.name,
        key: object_key,
      )
      true
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::S3::Errors::Forbidden
      raise Error::S3BucketForbidden.new
    end
  end

  def fetch
    fetch_project_if_necessary
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
    fetch_project_if_necessary
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
    fetch_project_if_necessary
    s3_client = s3_client(s3_bucket: project.remote_cache_storage)
    object = s3_client.get_object(
      bucket: project.remote_cache_storage.name,
      key: object_key
    )
    object.content_length
  end

  private def fetch_project_if_necessary
    if project.nil?
      @project = ProjectFetchService.new.fetch_by_name(
        name: project_name,
        account_name: account_name,
        user: user
      )
    end
  end

  private
    def s3_client(s3_bucket:)
      secret_access_key = DecipherService.call(
        key: Base64.decode64(s3_bucket.secret_access_key),
        iv: Base64.decode64(s3_bucket.iv)
      )
      Aws::S3::Client.new(
        region: s3_bucket.region,
        access_key_id: s3_bucket.access_key_id,
        secret_access_key: secret_access_key,
      )
    end
end
