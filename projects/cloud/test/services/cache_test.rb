# frozen_string_literal: true

require "test_helper"

class CacheServiceTest < ActiveSupport::TestCase
  test "object exists" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    s3_bucket = user.account.s3_buckets.create!(
      name: "project-bucket",
      access_key_id: "access key id",
      secret_access_key: "encoded secret",
      iv: "random iv"
    )
    project = Project.create!(
      name: "my-project",
      account_id: user.account.id,
      token: Devise.friendly_token.first(8),
      remote_cache_storage: s3_bucket
    )
    ProjectFetchService.stubs(:call).returns(project)
    DecipherService.stubs(:call).returns("decoded secret")
    Aws::S3::Client.any_instance.stubs(:head_object).returns(true)

    # When
    got = CacheService.new(
      project_slug: "my-project/tuist",
      hash: "artifact-hash",
      name: "MyFramework",
      user: user
    )
    .object_exists?

    # Then
    assert_equal got, true
  end

  test "object does not exists when not found AWS error is thrown" do
        # Given
        user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
        s3_bucket = user.account.s3_buckets.create!(
          name: "project-bucket",
          access_key_id: "access key id",
          secret_access_key: "encoded secret",
          iv: "random iv"
        )
        project = Project.create!(
          name: "my-project",
          account_id: user.account.id,
          token: Devise.friendly_token.first(8),
          remote_cache_storage: s3_bucket
        )
        ProjectFetchService.stubs(:call).returns(project)
        DecipherService.stubs(:call).returns("decoded secret")
        Aws::S3::Client.any_instance.stubs(:head_object).raises(Aws::S3::Errors::NotFound.new("", ""))

        # When
        got = CacheService.new(
          project_slug: "my-project/tuist",
          hash: "artifact-hash",
          name: "MyFramework",
          user: user
        )
        .object_exists?

        # Then
        assert_equal got, false
  end
end


# UserOrganizationsFetchService.stubs(:call).returns(
#   [
#     organizations[0],
#     organizations[2],
#   ]
# )
