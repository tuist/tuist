# frozen_string_literal: true

include Rails.application.routes.url_helpers

class CacheService < ApplicationService
  attr_reader :account_name, :project_name, :project_slug, :hash, :name, :user, :object_key, :project

  module Error
    class S3BucketForbidden < CloudError
      def message
        "Ensure your secret access key is set correctly, following the instructions here: https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html."
      end

      def status_code
        :bad_request
      end
    end

    class Unauthorized < CloudError
      def message
        "You do not have a permission to clear this S3 bucket."
      end

      def status_code
        :unauthorized
      end
    end

    class PaymentRequired < CloudError
      def message
        url = URI.parse(Environment.app_url).tap { |uri| uri.path = '/get-started' }.to_s

        "To use remote cache, you need to upgrade your plan. Please, visit #{url} to manage your subscription."
      end

      def status_code
        :payment_required
      end
    end
  end

  def initialize(project_slug:, hash:, name:, user:, project:)
    super()
    split_project_slug = project_slug.split("/")
    @account_name = split_project_slug.first
    @project_name = split_project_slug.last
    @project_slug = project_slug
    @hash = hash
    @object_key = "#{project_slug}/#{hash}/#{name}"
    @name = name
    @user = user
    @project = project
  end

  def object_exists?
    fetch_project_if_necessary
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    begin
      s3_client.head_object(
        bucket: project.remote_cache_storage.name,
        key: object_key,
      )
      true
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::S3::Errors::Forbidden
      raise Error::S3BucketForbidden
    end
  end

  def fetch
    fetch_project_if_necessary
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    signer = Aws::S3::Presigner.new(client: s3_client)
    url = signer.presigned_url(
      :get_object,
      bucket: project.remote_cache_storage.name,
      key: object_key,
    )
    url
  end

  def upload
    fetch_project_if_necessary
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    s3_client.put_object(
      bucket: project.remote_cache_storage.name,
      key: object_key,
    )
    signer = Aws::S3::Presigner.new(client: s3_client)
    url = signer.presigned_url(
      :put_object,
      bucket: project.remote_cache_storage.name,
      key: object_key,
    )
    url
  end

  def verify_upload
    fetch_project_if_necessary
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    object = s3_client.get_object(
      bucket: project.remote_cache_storage.name,
      key: object_key,
    )
    object.content_length
  end

  private def fetch_project_if_necessary
    if project.nil?
      @project = ProjectFetchService.new.fetch_by_name(
        name: project_name,
        account_name: account_name,
        user: user,
      )
    end

    if Environment.stripe_configured? && @project.account.owner.is_a?(Organization) && @project.account.plan.nil?
      raise Error::PaymentRequired
    end
  end
end
