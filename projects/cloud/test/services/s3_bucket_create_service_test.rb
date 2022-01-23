# frozen_string_literal: true

require "test_helper"

class S3BucketCreateServiceTest < ActiveSupport::TestCase
  test "creates an S3 bucket" do
    # Given
    bucket_name = "bucket"
    access_key_id = "access key id"
    secret_access_key = "secret access key"

    # When
    got = S3BucketCreateService.call(bucket_name: bucket_name, access_key_id: access_key_id, secret_access_key: secret_access_key)

    # Then
    assert_equal bucket_name, got.bucket_name
    assert_equal access_key_id, got.access_key_id
    assert_not_equal secret_access_key, got.secret_access_key
  end

  test "creating an S3 bucket fails when another with the same name already exists" do
    # TODO: Implement
  end
end
