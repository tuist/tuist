# frozen_string_literal: true

class CacheService < ApplicationService
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

  attr_reader :account_name, :project_name, :project_slug, :hash, :name, :object_key, :subject, :cache_category

  def initialize(project_slug:, cache_category: nil, hash:, name:, subject:)
    super()
    split_project_slug = project_slug.split("/")
    @account_name = split_project_slug.first
    @project_name = split_project_slug.last
    @project_slug = project_slug
    @hash = hash
    @object_key = if cache_category.nil? || cache_category.empty?
      "#{project_slug}/#{hash}/#{name}"
    else
      "#{project_slug}/#{cache_category}/#{hash}/#{name}"
    end

    @name = name
    @subject = subject
  end

  def object_exists?
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    begin
      object = s3_client.get_object(
        bucket: project.remote_cache_storage.name,
        key: object_key,
      )
      object.content_length > 0
    rescue Aws::S3::Errors::NoSuchKey
      false
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::S3::Errors::Forbidden
      raise Error::S3BucketForbidden
    end
  end

  def fetch
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    signer = Aws::S3::Presigner.new(client: s3_client)
    url = signer.presigned_url(
      :get_object,
      bucket: project.remote_cache_storage.name,
      key: object_key,
    )
    upload_event = CacheEvent.where(name: object_key, event_type: :upload).first
    unless upload_event.nil?
      CacheEvent.create!(
        name: object_key,
        event_type: :download,
        size: upload_event.size,
        project_id: project.id,
      )
    end
    url
  end

  def upload
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
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    object = s3_client.get_object(
      bucket: project.remote_cache_storage.name,
      key: object_key,
    )
    CacheEvent.create!(
      name: object_key,
      event_type: :upload,
      size: object.content_length,
      project_id: project.id,
    )
    object.content_length
  end

  def project
    @project ||= ProjectFetchService.new.fetch_by_name(
      name: project_name,
      account_name: account_name,
      subject: subject,
    )
    # Disabled for now
    # if Environment.stripe_configured? && @project.account.owner.is_a?(Organization) && @project.account.plan.nil?
    #   raise Error::PaymentRequired
    # end
  end
end
