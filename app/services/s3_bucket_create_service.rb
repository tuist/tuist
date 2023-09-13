# frozen_string_literal: true

class S3BucketCreateService < ApplicationService
  attr_reader :name, :access_key_id, :secret_access_key, :region, :account_id

  module Error
    class DuplicatedName < CloudError
      attr_reader :name

      def initialize(name)
        super
        @name = name
      end

      def message
        "Bucket #{name} already exists."
      end
    end
  end

  def initialize(name:, access_key_id:, secret_access_key:, region:, account_id:)
    super()
    @name = name
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
    @region = region
    @account_id = account_id
  end

  def call
    unless S3Bucket.find_by(name: name, account_id: account_id).nil?
      raise Error::DuplicatedName, name
    end

    cipher = OpenSSL::Cipher.new('aes-256-cbc')
    cipher.encrypt
    cipher.key = Digest::MD5.hexdigest(Environment.secret_key_base)
    iv = cipher.random_iv

    encrypted_secret_access_key = cipher.update(secret_access_key) + cipher.final
    if account_id.nil?
      S3Bucket.create!(
        name: name,
        access_key_id: access_key_id,
        secret_access_key: Base64.encode64(encrypted_secret_access_key),
        iv: Base64.encode64(iv),
        region: region,
      )
    else
      account = Account.find(account_id)
      account.s3_buckets.create!(
        name: name,
        access_key_id: access_key_id,
        secret_access_key: Base64.encode64(encrypted_secret_access_key),
        iv: Base64.encode64(iv),
        region: region,
      )
    end
  end
end
