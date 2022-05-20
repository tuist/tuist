# frozen_string_literal: true

class S3BucketUpdateService < ApplicationService
  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to change this S3 bucket."
      end
    end

    class S3BucketNotFound < CloudError
      attr_reader :bucket_id

      def initialize(bucket_id)
        @bucket_id
      end

      def message
        "S3 bucket with the id #{bucket_id} was not found."
      end
    end
  end

  attr_reader :id, :name, :access_key_id, :secret_access_key, :region, :user

  def initialize(id:, name:, access_key_id:, secret_access_key:, region:, user:)
    super()
    @id = id
    @name = name
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
    @region = region
    @user = user
  end

  def call
    begin
      bucket = S3Bucket.find(id)
    rescue ActiveRecord::RecordNotFound
      raise Error::S3BucketNotFound.new(id)
    end
    raise Error::Unauthorized.new unless AccountPolicy.new(user, bucket.account).update?

    if secret_access_key != bucket.secret_access_key
      cipher = OpenSSL::Cipher::AES.new(256, :CBC)
      cipher.encrypt
      cipher.key = Digest::MD5.hexdigest(Rails.application.credentials[:secret_key_base])
      iv = cipher.random_iv

      encrypted_secret_access_key = cipher.update(secret_access_key) + cipher.final
      bucket.update(
        name: name,
        access_key_id: access_key_id,
        secret_access_key: Base64.encode64(encrypted_secret_access_key),
        region: region,
        iv: Base64.encode64(iv)
      )
    else
      bucket.update(
        name: name,
        access_key_id: access_key_id,
        region: region
      )
    end
    bucket
  end
end
