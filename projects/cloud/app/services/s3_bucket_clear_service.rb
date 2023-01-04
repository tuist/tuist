# frozen_string_literal: true

class S3BucketClearService < ApplicationService
  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to clear this S3 bucket."
      end
    end

    class S3BucketNotFound < CloudError
      def message
        "S3 bucket was not found. Make sure it exists."
      end
    end
  end

  attr_reader :id, :clearer

  def initialize(id:, clearer:)
    super()
    @id = id
    @clearer = clearer
  end

  def call
    begin
      bucket = S3Bucket.find(id)
    rescue ActiveRecord::RecordNotFound
      raise Error::S3BucketNotFound
    end
    raise Error::Unauthorized.new unless AccountPolicy.new(clearer, bucket.account).update?

    s3_bucket = s3_bucket(bucket: bucket)
    s3_bucket.clear!

    bucket
  end

  def s3_bucket(bucket:)
    secret_access_key = DecipherService.call(
      key: Base64.decode64(bucket.secret_access_key),
      iv: Base64.decode64(bucket.iv),
    )
    Aws::S3::Bucket.new(
      name: bucket.name,
      region: bucket.region,
      access_key_id: bucket.access_key_id,
      secret_access_key: secret_access_key,
    )
  end
end
