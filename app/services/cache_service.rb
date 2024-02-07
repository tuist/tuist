# typed: strict
# frozen_string_literal: true

class CacheService < ApplicationService
  extend T::Sig

  module Error
    class S3BucketForbidden < CloudError
      extend T::Sig

      sig { returns(String) }
      def message
        "Ensure your secret access key is set correctly, following the instructions here: https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html."
      end

      sig { returns(Symbol) }
      def status_code
        :bad_request
      end
    end

    class Unauthorized < CloudError
      extend T::Sig

      sig { returns(String) }
      def message
        "You do not have a permission to clear this S3 bucket."
      end

      sig { returns(Symbol) }
      def status_code
        :unauthorized
      end
    end

    class PaymentRequired < CloudError
      extend T::Sig

      sig { returns(String) }
      def message
        # rubocop:disable Layout/LineLength
        "Your account is over the 30-day free limit of #{FORMATTED_THRESHOLD} cache uploads on Tuist Cloud. To continue enjoying this service, please reach out to us at help@tuist.io for a quote on a Tuist Cloud plan."
        # rubocop:enable Layout/LineLength
      end

      sig { returns(Symbol) }
      def status_code
        :payment_required
      end
    end
  end

  sig { returns(String) }
  attr_reader :account_name

  sig { returns(String) }
  attr_reader :project_name

  sig { returns(String) }
  attr_reader :project_slug

  sig { returns(String) }
  attr_reader :hash

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.any(User, Organization, Project)) }
  attr_reader :subject

  sig { returns(T.nilable(String)) }
  attr_reader :cache_category

  sig { returns(String) }
  attr_reader :object_key

  sig { returns(T.proc.params(message: String).void) }
  attr_reader :add_cloud_warning

  sig do
    params(
      project_slug: String,
      hash: String,
      name: String,
      subject: T.any(User, Organization, Project),
      add_cloud_warning: T.proc.params(message: String).void,
      cache_category: T.nilable(String),
    ).void
  end
  def initialize(project_slug:, hash:, name:, subject:, add_cloud_warning:, cache_category: nil)
    super()
    split_project_slug = project_slug.split("/")
    @account_name = T.let(T.must(T.let(split_project_slug.first, T.nilable(String))), String)
    @project_name = T.let(T.must(T.let(split_project_slug.last, T.nilable(String))), String)
    @project_slug = project_slug
    @hash = hash
    @cache_category = T.let(cache_category, T.nilable(String))
    @object_key = T.let(
      if cache_category.nil? || cache_category.empty?
        T.let("#{project_slug}/#{hash}/#{name}", String)
      else
        T.let("#{project_slug}/#{cache_category}/#{hash}/#{name}", String)
      end,
      String,
    )

    @name = name
    @subject = subject
    @add_cloud_warning = T.let(add_cloud_warning, T.proc.params(arg0: String).void)
  end

  sig { returns(T::Boolean) }
  def object_exists?
    check_if_plan_valid
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

  sig { returns(String) }
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

  sig { returns(String) }
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

  sig { returns(String) }
  def multipart_upload_start
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    upload = s3_client.create_multipart_upload({
      bucket: project.remote_cache_storage.name,
      key: object_key,
    })
    upload.upload_id
  end

  sig { params(upload_id: String, part_number: Integer).returns(String) }
  def multipart_generate_url(upload_id:, part_number:)
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    presigner = Aws::S3::Presigner.new(client: s3_client)

    presigner.presigned_url(:upload_part, {
      bucket: project.remote_cache_storage.name,
      key: object_key,
      upload_id: upload_id,
      part_number: part_number,
    })
  end

  sig { params(upload_id: String, parts: T::Array[{ part_number: Integer, etag: String }]).returns(NilClass) }
  def multipart_upload_complete(upload_id:, parts:)
    s3_client = S3ClientService.call(s3_bucket: project.remote_cache_storage)
    s3_client.complete_multipart_upload({
      bucket: project.remote_cache_storage.name,
      key: object_key,
      upload_id: upload_id,
      multipart_upload: {
        parts: parts,
      },
    })
  end

  sig { returns(Integer) }
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

  sig { returns(Project) }
  def project
    @project ||= T.let(
      ProjectFetchService.new.fetch_by_name(
        name: project_name,
        account_name: account_name,
        subject: subject,
      ),
      T.nilable(Project),
    )
    @project
  end

  private

  THRESHOLD = T.let(10_000, Integer)
  FORMATTED_THRESHOLD = T.let(ActiveSupport::NumberHelper.number_to_delimited(THRESHOLD), String)

  sig { void }
  def check_if_plan_valid
    if Environment.stripe_configured? && T.must(project.account).plan.nil?
      if T.must(T.must(project.account).cache_upload_event_count) > THRESHOLD
        raise Error::PaymentRequired
      elsif T.must(T.must(project.account).cache_upload_event_count) > THRESHOLD * 0.8
        # rubocop:disable Layout/LineLength
        add_cloud_warning.call("Your account is nearing the 30-day free limit of #{FORMATTED_THRESHOLD} cache uploads on Tuist Cloud. Once this limit is reached, you won't be able to use Tuist Cloud's remote caching feature. To continue enjoying this service, please reach out to us at help@tuist.io for a quote on a Tuist Cloud plan.")
        # rubocop:enable Layout/LineLength
      end
    end
  end
end
