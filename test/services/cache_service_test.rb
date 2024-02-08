# frozen_string_literal: true
# typed: false

require "test_helper"

class CacheServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    @user.account.update(plan: :enterprise)
    @s3_bucket = @user.account.s3_buckets.create!(
      name: "project-bucket",
      access_key_id: "access key id",
      secret_access_key: "encoded secret",
      iv: "random iv",
      region: "region",
    )
    @project = Project.create!(
      name: "my-project",
      account_id: @user.account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket,
    )
    ProjectFetchService.any_instance.stubs(:fetch_by_name).returns(@project)
    DecipherService.stubs(:call).returns("decoded secret")
  end

  test "object exists" do
    # Given
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).returns(bucket_object)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @user,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "uses default bucket when remote storage is not defined" do
    # Given
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).returns(bucket_object)
    @project.update(remote_cache_storage: nil)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "object exists with using passed project" do
    # Given
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).returns(bucket_object)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "object exists when cache_category is not specified" do
    # Given
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).returns(bucket_object)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "object does not exist when not found AWS error is thrown" do
    # Given
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).raises(Aws::S3::Errors::NotFound.new("", ""))

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @user,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal false, got
  end

  test "object does not exist when no such key AWS error is thrown" do
    # Given
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).raises(Aws::S3::Errors::NoSuchKey.new("", ""))

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @user,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal false, got
  end

  test "catches forbidden AWS error" do
    # Given
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).raises(Aws::S3::Errors::Forbidden.new("", ""))

    # When / Then
    assert_raises(CacheService::Error::S3BucketForbidden) do
      CacheService.new(
        project_slug: "my-project/tuist",
        hash: "artifact-hash",
        name: "MyFramework",
        subject: @project,
        cache_category: "builds",
        add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
      )
        .object_exists?
    end
  end

  test "fetch returns presigned url for uploading file" do
    # Given
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    Aws::S3::Presigner.any_instance.stubs(:presigned_url).returns("download url")
    CacheEvent.create!(
      name: "my-project/tuist/builds/artifact-hash/MyFramework",
      event_type: :upload,
      size: 10,
      project_id: @project.id,
    )

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @user,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .fetch

    # Then
    assert_equal CacheEvent.count, 2
    assert_equal CacheEvent.last.name, "my-project/tuist/builds/artifact-hash/MyFramework"
    assert_equal CacheEvent.last.event_type, "download"
    assert_equal CacheEvent.last.size, 10
    assert_equal CacheEvent.last.project, @project
    assert_equal "download url", got
  end

  test "fetch returns presigned url for uploading file for tests cache_category" do
    # Given
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)

    Aws::S3::Presigner.any_instance.stubs(:presigned_url).returns("download url")
    CacheEvent.create!(
      name: "my-project/tuist/tests/artifact-hash/MyFramework",
      event_type: :upload,
      size: 10,
      project_id: @project.id,
    )

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @user,
      cache_category: "tests",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .fetch

    # Then
    assert_equal CacheEvent.count, 2
    assert_equal CacheEvent.last.name, "my-project/tuist/tests/artifact-hash/MyFramework"
    assert_equal CacheEvent.last.event_type, "download"
    assert_equal CacheEvent.last.size, 10
    assert_equal CacheEvent.last.project, @project
    assert_equal "download url", got
  end

  test "upload returns presigned url for uploading file" do
    # Given
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:put_object)
    Aws::S3::Presigner.any_instance.stubs(:presigned_url).returns("upload url")

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @user,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .upload

    # Then
    assert_equal "upload url", got
  end

  test "verify upload returns content length" do
    # Given
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).returns(bucket_object)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: @user,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .verify_upload

    # Then
    assert_equal CacheEvent.count, 1
    assert_equal CacheEvent.first.name, "my-project/tuist/builds/artifact-hash/MyFramework"
    assert_equal CacheEvent.first.event_type, "upload"
    assert_equal CacheEvent.first.size, 5
    assert_equal CacheEvent.first.project, @project
    assert_equal got, 5
  end

  test "fails with payment required if an organization has no plan" do
    # Given
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist", plan: nil)
    project = Project.create!(
      name: "my-project",
      account_id: account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket,
    )
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    ProjectFetchService.any_instance.stubs(:fetch_by_name).returns(project)

    project.account.update(cache_upload_event_count: 15_000)

    # When / Then
    assert_raises(CacheService::Error::PaymentRequired) do
      CacheService.new(
        project_slug: "my-project/tuist",
        hash: "artifact-hash",
        name: "MyFramework",
        subject: project,
        cache_category: "builds",
        add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
      )
        .object_exists?
    end
  end

  test "fails with payment required if an organization has no plan and is close to the limit" do
    # Given
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist", plan: nil)
    project = Project.create!(
      name: "my-project",
      account_id: account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket,
    )
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).returns(bucket_object)
    ProjectFetchService.any_instance.stubs(:fetch_by_name).returns(project)

    project.account.update(cache_upload_event_count: 8_500)
    add_cloud_warning = mock
    add_cloud_warning.expects(:call)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "object exists with using passed project when an organization's plan is enterprise" do
    # Given
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist", plan: :enterprise)
    project = Project.create!(
      name: "my-project",
      account_id: organization.account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket,
    )
    bucket_object = mock
    bucket_object.stubs(:content_length).returns(5)
    s3_client = mock('s3-client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns(s3_client)
    s3_client.expects(:get_object).returns(bucket_object)

    project.account.update(cache_upload_event_count: 15_000)
    add_cloud_warning = mock
    add_cloud_warning.expects(:call).never

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      subject: project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "multipart_upload_start creates the upload using the Aws::S3::Client" do
    # Given
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist", plan: :enterprise)
    project = Project.create!(
      name: "my-project",
      account_id: organization.account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket,
    )
    subject = CacheService.new(
      project_slug: project.full_name,
      hash: "artifact-hash",
      name: "MyFramework",
      subject: project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
    s3_client = mock('Aws::S3::Client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns([s3_client, "bucket"])
    s3_client.expects(:create_multipart_upload).with({
      bucket: "bucket",
      key: subject.object_key,
    }).returns(Struct.new(:upload_id).new(upload_id: "upload_id"))

    # When
    got = subject.multipart_upload_start

    # Then
    assert_equal "upload_id", got
  end

  test "multipart_generate_url generates the URL using the Aws::S3::Client" do
    # Given
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist", plan: :enterprise)
    project = Project.create!(
      name: "my-project",
      account_id: organization.account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket,
    )
    add_cloud_warning = mock
    subject = CacheService.new(
      project_slug: project.full_name,
      hash: "artifact-hash",
      name: "MyFramework",
      subject: project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
    s3_client = mock('Aws::S3::Client').responds_like_instance_of(Aws::S3::Client)
    presigner = mock('Aws::S3::Presigner').responds_like_instance_of(Aws::S3::Presigner)
    S3ClientService.expects(:call).returns([s3_client, "bucket"])
    Aws::S3::Presigner.expects(:new).returns(presigner)
    upload_url = "https://test.upload.com/"
    presigner.expects(:presigned_url).with(:upload_part, {
      bucket: "bucket",
      key: subject.object_key,
      upload_id: "upload_id",
      part_number: 1,
    }).returns(upload_url)

    # When
    got = subject.multipart_generate_url(upload_id: "upload_id", part_number: 1)

    # Then
    assert_equal upload_url, got
  end

  test "multipart_upload_complete completes the upload using the Aws::S3::Client" do
    # Given
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist", plan: :enterprise)
    project = Project.create!(
      name: "my-project",
      account_id: organization.account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket,
    )
    add_cloud_warning = mock
    subject = CacheService.new(
      project_slug: project.full_name,
      hash: "artifact-hash",
      name: "MyFramework",
      subject: project,
      cache_category: "builds",
      add_cloud_warning: ->(message) { add_cloud_warning.call(message) },
    )
    s3_client = mock('Aws::S3::Client').responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns([s3_client, "bucket"])
    s3_client.expects(:complete_multipart_upload).with({
      bucket: "bucket",
      key: subject.object_key,
      upload_id: "upload_id",
      multipart_upload: {
        parts: [{ part_number: 1, etag: "etag" }],
      },
    })

    # When/Then
    subject.multipart_upload_complete(upload_id: "upload_id", parts: [{ part_number: 1, etag: "etag" }])
  end
end
