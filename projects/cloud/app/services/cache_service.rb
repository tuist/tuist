# frozen_string_literal: true

class CacheService < ApplicationService
  attr_reader :account_name, :project_name, :hash, :name, :user, :object_key, :project

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
      @project = ProjectFetchService.call(
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
