# frozen_string_literal: true

class CacheArtifactUploadService < ApplicationService
  attr_reader :project_slug, :hash, :name, :user

  def initialize(project_slug:, hash:, name:, user:)
    super()
    @project_slug = project_slug
    @hash = hash
    @name = name
    @user = user
  end

  def call
    split_project_slug = project_slug.split("/")
    account_name = split_project_slug.first
    project_name = split_project_slug.last
    project = ProjectFetchService.call(name: project_name, account_name: account_name, user: user)
    # account = AccountFetchService.call(name: account_name)
    decipher = OpenSSL::Cipher::AES.new(256, :CBC)
    decipher.decrypt
    decipher.key = Digest::MD5.hexdigest(Rails.application.credentials[:secret_key_base])
    decipher.iv = Base64.decode64(project.remote_cache_storage.iv)
    secret_access_key = Base64.decode64(project.remote_cache_storage.secret_access_key)
    s3_client = Aws::S3::Client.new(
      # TODO: Add this to database and make it configurable
      region: 'eu-central-1',
      access_key_id: project.remote_cache_storage.access_key_id,
      secret_access_key: decipher.update(secret_access_key) + decipher.final,
    )
    upload_object(s3_client, project.remote_cache_storage.name, "#{hash}/#{name}")
  end

  def upload_object(s3_client, bucket_name, object_key)
    # begin
      response = s3_client.put_object(
        bucket: bucket_name,
        key: object_key
      )
      puts response
      response
    # rescue StandardError => e
      # puts "Error uploading object: #{e.message}"
    # end
  end
end
