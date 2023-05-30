# frozen_string_literal: true

require "test_helper"

class S3BucketClearServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    @s3_bucket = @user.account.s3_buckets.create!(
      name: "project-bucket",
      access_key_id: "access key id",
      secret_access_key: "encoded secret",
      iv: "random iv",
      region: "region",
    )
    DecipherService.stubs(:call).returns("decoded secret")
  end

  test "cache is cleared" do
    # Given
    Aws::S3::Bucket.any_instance.stubs(:clear!)

    # When
    got = S3BucketClearService.call(
      id: @s3_bucket.id,
      clearer: @user,
    )

    # Then
    assert_equal @s3_bucket, got
  end

  test "cache is cleared with project slug" do
    # Given
    Aws::S3::Bucket.any_instance.stubs(:clear!)
    project = Project.create!(
      name: "tuist-project",
      account_id: @user.account.id,
      token: Devise.friendly_token.first(16))
    project.remote_cache_storage = @s3_bucket
    ProjectFetchService.any_instance.stubs(:fetch_by_slug).returns(project)

    # When
    got = S3BucketClearService.call(
      project_slug: "project/slug",
      clearer: @user,
    )

    # Then
    assert_equal @s3_bucket, got
  end
end
