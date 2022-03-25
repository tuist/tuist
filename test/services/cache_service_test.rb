# frozen_string_literal: true

require "test_helper"

class CacheServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    @s3_bucket = @user.account.s3_buckets.create!(
      name: "project-bucket",
      access_key_id: "access key id",
      secret_access_key: "encoded secret",
      iv: "random iv",
      region: "region"
    )
    @project = Project.create!(
      name: "my-project",
      account_id: @user.account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: @s3_bucket
    )
    ProjectFetchService.stubs(:call).returns(@project)
    DecipherService.stubs(:call).returns("decoded secret")
  end

  test "object exists" do
    # Given
    Aws::S3::Client.any_instance.stubs(:head_object).returns(true)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      user: @user,
      project: nil
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "object exists with using passed project" do
    # Given
    Aws::S3::Client.any_instance.stubs(:head_object).returns(true)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      user: nil,
      project: @project
    )
      .object_exists?

    # Then
    assert_equal true, got
  end

  test "object does not exists when not found AWS error is thrown" do
    # Given
    Aws::S3::Client.any_instance.stubs(:head_object).raises(Aws::S3::Errors::NotFound.new("", ""))

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      user: @user,
      project: nil
    )
      .object_exists?

    # Then
    assert_equal false, got
  end

  test "upload returns presigned url for uploading file" do
    # Given
    Aws::S3::Client.any_instance.stubs(:put_object)
    Aws::S3::Presigner.any_instance.stubs(:presigned_url).returns("upload url")

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      user: @user,
      project: nil
    )
      .upload

    # Then
    assert_equal "upload url", got
  end

  test "verify upload returns content length" do
    # Given
    bucket_object = mock()
    bucket_object.stubs(:content_length).returns(5)
    Aws::S3::Client.any_instance.stubs(:get_object).returns(bucket_object)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      user: @user,
      project: nil
    )
      .verify_upload

    # Then
    assert_equal got, 5
  end
end
