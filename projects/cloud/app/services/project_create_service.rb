# frozen_string_literal: true

class ProjectCreateService < ApplicationService
  attr_reader :creator, :name, :organization_name, :account_id

  def initialize(creator:, name:, organization_name: nil, account_id: nil)
    super()
    @creator = creator
    @name = name
    @organization_name = organization_name
    @account_id = account_id
  end

  def call
    ActiveRecord::Base.transaction do
      if organization_name.nil?
        project = Project.create!(name: name, account_id: account_id, token: Devise.friendly_token.first(8))
      else
        organization = OrganizationCreateService.call(creator: creator, name: organization_name)
        project = Project.create!(
          name: name,
          account_id: organization.account.id,
          token: Devise.friendly_token.first(8)
        )
      end
      s3_bucket_name = "#{project.account.name}-#{name}"
      s3_client.create_bucket(bucket: s3_bucket_name)
      s3_bucket = S3BucketCreateService.call(
        name: s3_bucket_name,
        access_key_id: Rails.application.credentials.aws[:access_key_id],
        secret_access_key: Rails.application.credentials.aws[:secret_access_key],
        region: "eu-west-1",
        account_id: organization_name.nil? ? account_id : organization.account.id,
        is_default: true
      )
      project.update(remote_cache_storage: s3_bucket)
      project
    end
  end

  def s3_client
    Aws::S3::Client.new(
      region: "eu-west-1",
      access_key_id: Rails.application.credentials.aws[:access_key_id],
      secret_access_key: Rails.application.credentials.aws[:secret_access_key],
    )
  end
end
