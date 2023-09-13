# frozen_string_literal: true

class S3ClientService < ApplicationService
  attr_reader :s3_bucket

  def initialize(s3_bucket:)
    super()
    @s3_bucket = s3_bucket
  end

  def call
    secret_access_key = if s3_bucket.iv.nil?
      s3_bucket.secret_access_key
    else
      DecipherService.call(
        key: Base64.decode64(s3_bucket.secret_access_key),
        iv: Base64.decode64(s3_bucket.iv),
      )
    end
    Aws::S3::Client.new(
      region: s3_bucket.region,
      access_key_id: s3_bucket.access_key_id,
      secret_access_key: secret_access_key,
    )
  end
end
