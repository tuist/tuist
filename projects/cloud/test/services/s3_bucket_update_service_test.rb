# frozen_string_literal: true

require "test_helper"

class S3BucketCreateServiceTest < ActiveSupport::TestCase
  test "updates an S3 bucket" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    s3_bucket = user.account.s3_buckets.create!(
      access_key_id: "1",
      name: "s3 bucket",
      secret_access_key: "secret"
    )

    # When
    got = S3BucketUpdateService.call(
      id: s3_bucket.id,
      name: "new name",
      access_key_id: "new access key",
      secret_access_key: "new secret access key",
      user: user
    )

    # Then
    assert_equal "new name", got.name
    assert_equal "new access key", got.access_key_id
    assert_not_equal "new secret access key", got.secret_access_key
    assert_not_equal s3_bucket.secret_access_key, got.secret_access_key
    assert_not_equal s3_bucket.iv, got.iv
    assert_equal user.account.id, got.account_id
  end

  test "updating an S3 bucket fails when the bucket with a given id does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When/Then
    assert_raises(S3BucketUpdateService::Error::S3BucketNotFound) do
      S3BucketUpdateService.call(
        id: "some id",
        name: "new name",
        access_key_id: "new access key",
        secret_access_key: "new secret access key",
        user: user
      )
    end
  end

  test "updating an S3 bucket fails when the user is unauthorized to change it" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    s3_bucket = account.s3_buckets.create!(
      access_key_id: "1",
      name: "s3 bucket",
      secret_access_key: "secret"
    )

    # When/Then
    assert_raises(S3BucketUpdateService::Error::Unauthorized) do
      S3BucketUpdateService.call(
        id: s3_bucket.id,
        name: "new name",
        access_key_id: "new access key",
        secret_access_key: "new secret access key",
        user: user
      )
    end
  end
end
