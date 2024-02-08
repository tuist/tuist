# frozen_string_literal: true

class S3ClientService < ApplicationService
  def call
    client = Aws::S3::Client.new(
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      endpoint: Environment.s3_endpoint,
    )
    [client, bucket_name]
  end

  private

  def bucket_name
    Environment.s3_bucket_name
  end

  def region
    Environment.s3_region
  end

  def access_key_id
    Environment.s3_access_key_id
  end

  def secret_access_key
    Environment.s3_secret_access_key
  end
end
