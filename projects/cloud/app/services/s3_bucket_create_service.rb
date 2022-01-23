# frozen_string_literal: true

class S3BucketCreateService < ApplicationService
  attr_reader :bucket_name, :access_key_id, :secret_access_key

  module Error
    class DuplicatedName < CloudError
      attr_reader :bucket_name

      def initialize(bucket_name)
        @bucket_name = bucket_name
      end

      def message
        "Bucket #{bucket_name} already exists."
      end
    end
  end

  def initialize(bucket_name:, access_key_id:, secret_access_key:)
    super()
    @bucket_name = bucket_name
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
  end

  def call
    if !S3Bucket.find_by(bucket_name: bucket_name).nil?
      raise Error::DuplicatedName.new(bucket_name)
    end
    cipher = OpenSSL::Cipher::AES.new(256, :CBC)
    cipher.encrypt
    cipher.key = Digest::MD5.hexdigest(Rails.application.credentials[:secret_key_base])
    iv = cipher.random_iv

    encrypted_secret_access_key = cipher.update(secret_access_key) + cipher.final

    S3Bucket.create!(bucket_name: bucket_name, access_key_id: access_key_id, secret_access_key: Base64.encode64(encrypted_secret_access_key), iv: iv)
  end
end
