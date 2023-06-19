# frozen_string_literal: true

class S3BucketCreateService < ApplicationService
  attr_reader :name, :access_key_id, :secret_access_key, :region, :account_id, :default_project

  module Error
    class DuplicatedName < CloudError
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def message
        "Bucket #{name} already exists."
      end
    end
  end

  def initialize(name:, access_key_id:, secret_access_key:, region:, account_id:, default_project: nil)
    super()
    @name = name
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
    @region = region
    @account_id = account_id
    @default_project = default_project
  end

  def call
    if !S3Bucket.find_by(name: name, account_id: account_id).nil?
      raise Error::DuplicatedName.new(name)
    end

    cipher = OpenSSL::Cipher::AES.new(256, :CBC)
    cipher.encrypt
    cipher.key = Digest::MD5.hexdigest(Rails.application.credentials[:secret_key_base])
    iv = cipher.random_iv

    encrypted_secret_access_key = cipher.update(secret_access_key) + cipher.final
    account = Account.find(account_id)
    account.s3_buckets.create!(
      name: name,
      access_key_id: access_key_id,
      secret_access_key: Base64.encode64(encrypted_secret_access_key),
      iv: Base64.encode64(iv),
      region: region,
      is_default: default_project.nil? == false,
      default_project_id: !default_project.nil? ? default_project.id : nil,
    )
  end
end
