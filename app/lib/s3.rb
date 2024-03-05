# frozen_string_literal: true

class S3
  include Singleton
  attr_reader :bucket, :region, :access_key_id, :secret_access_key, :endpoint, :client

  def initialize
    @bucket = Environment.s3_bucket_name
    @region = Environment.s3_region
    @access_key_id = Environment.s3_access_key_id
    @secret_access_key = Environment.s3_secret_access_key
    @endpoint = Environment.s3_endpoint
    @client = Aws::S3::Client.new(
      region: @region,
      access_key_id: @access_key_id,
      secret_access_key: @secret_access_key,
      endpoint: @endpoint,
    )
  end
end
