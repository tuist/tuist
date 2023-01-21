# frozen_string_literal: true

class ProjectCreateService < ApplicationService
  module Error
    class ProjectAlreadyExists < CloudError
      attr_reader :name, :account_name

      def initialize(name, account_name)
        @name = name
        @account_name = account_name
      end

      def message
        "Project #{account_name}/#{name} already exists"
      end
    end
  end
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
        if account_id.nil?
          @account_id = creator.account.id
        end
        if Project.exists?(name: name, account_id: account_id)
          account = Account.find(account_id)
          raise Error::ProjectAlreadyExists.new(name, account.name)
        end
        project = Project.create!(name: name, account_id: account_id, token: Devise.friendly_token.first(8))
      else
        organization = OrganizationCreateService.call(creator: creator, name: organization_name)
        project = Project.create!(
          name: name,
          account_id: organization.account.id,
          token: Devise.friendly_token.first(8),
        )
      end
      create_s3_bucket(project, organization)
      project
    end
  end

  def create_s3_bucket(project, organization)
    # A prefix is added as the bucket name must be unique across the whole AWS and not just across the tuist one.
    s3_bucket_name = "#{SecureRandom.uuid[0...-13]}-#{project.account.name}-#{name}"
    s3_bucket = S3BucketCreateService.call(
      name: s3_bucket_name,
      access_key_id: Rails.application.credentials.aws[:access_key_id],
      secret_access_key: Rails.application.credentials.aws[:secret_access_key],
      region: "eu-west-1",
      account_id: organization.nil? ? account_id : organization.account.id,
      default_project: project,
    )
    project.update(remote_cache_storage: s3_bucket)
    s3_client.create_bucket(bucket: s3_bucket_name)
    project
  end

  def s3_client
    Aws::S3::Client.new(
      region: "eu-west-1",
      access_key_id: Rails.application.credentials.aws[:access_key_id],
      secret_access_key: Rails.application.credentials.aws[:secret_access_key],
    )
  end
end
