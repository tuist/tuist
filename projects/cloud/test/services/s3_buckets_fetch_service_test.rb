# frozen_string_literal: true

require "test_helper"

class S3BucketsFetchServiceTest < ActiveSupport::TestCase
  test "fetches S3 buckets with a given account name" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    s3_bucket_one = account.s3_buckets.create!(
      access_key_id: "1",
      name: "s3 bucket one",
      secret_access_key: "secret",
      region: "region"
    )
    s3_bucket_two = account.s3_buckets.create!(
      access_key_id: "2",
      name: "s3 bucket two",
      secret_access_key: "secret",
      region: "region"
    )

    # When
    got = S3BucketsFetchService.call(account_name: account.name, user: user)

    # Then
    assert_equal [s3_bucket_one, s3_bucket_two], got
  end

  test "fails to fetch S3 buckets if user does not have rights to access them" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")

    # When / Then
    assert_raises(S3BucketsFetchService::Error::Unauthorized) do
      S3BucketsFetchService.call(account_name: account.name, user: user)
    end
  end
end
