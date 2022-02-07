# frozen_string_literal: true

require "test_helper"

class S3BucketCreateServiceTest < ActiveSupport::TestCase
  test "updates an S3 bucket" do
    # Given
    name = "bucket"
    access_key_id = "access key id"
    secret_access_key = "secret access key"
    account = Account.create!(owner: Organization.create!, name: "tuist")
    s3_bucket = account.s3_buckets.create!(
      access_key_id: "1",
      name: "s3 bucket one",
      secret_access_key: "secret"
    )

    # When
    got = S3BucketCreateService.call(
      name: name,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      account_id: account.id
    )

    # Then
    assert_equal name, got.name
    assert_equal access_key_id, got.access_key_id
    assert_not_equal secret_access_key, got.secret_access_key
    assert_equal account.id, got.account_id
  end

  test "creating an S3 bucket fails when another with the same name already exists" do
    # Given
    account = Account.create!(owner: Organization.create!, name: "tuist")
    S3BucketCreateService.call(
      name: "bucket",
      access_key_id: "key id 1",
      secret_access_key: "secret access key",
      account_id: account.id
    )

    # When/Then
    assert_raises(S3BucketCreateService::Error::DuplicatedName) do
      S3BucketCreateService.call(
        name: "bucket",
        access_key_id: "key id 2",
        secret_access_key: "secret access key",
        account_id: account.id
      )
    end
  end
end
