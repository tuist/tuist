# frozen_string_literal: true

require "test_helper"

class ProjectChangeRemoteCacheStorageServiceTest < ActiveSupport::TestCase
  test "fetches a project with a given name account_name" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    project = Project.create!(name: "tuist-project-2", account_id: account.id, token: Devise.friendly_token.first(16))
    s3_bucket = account.s3_buckets.create!(
      name: "s3-bucket",
      access_key_id: "access key id",
      region: "region"
    )

    # When
    got = ProjectChangeRemoteCacheStorageService.call(id: s3_bucket.id, project_id: project.id, user: user)

    # Then
    assert_equal s3_bucket.id, got.id
    assert_equal Project.find(project.id).remote_cache_storage, s3_bucket
  end

  test "fails to change remote cache storage if user is not admin" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    s3_bucket = account.s3_buckets.create!(
      name: "s3-bucket",
      access_key_id: "access key id",
      region: "region"
    )

    # When / Then
    assert_raises(ProjectChangeRemoteCacheStorageService::Error::Unauthorized) do
      ProjectChangeRemoteCacheStorageService.call(id: s3_bucket.id, project_id: project.id, user: user)
    end
  end

  test "fails with project not found if the project does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    s3_bucket = account.s3_buckets.create!(
      name: "s3-bucket",
      access_key_id: "access key id",
      region: "region"
    )

    # When / Then
    assert_raises(ProjectChangeRemoteCacheStorageService::Error::ProjectNotFound) do
      ProjectChangeRemoteCacheStorageService.call(id: s3_bucket.id, project_id: "project-non-existent", user: user)
    end
  end

  test "fails with bucket not found if the bucket does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    project = Project.create!(name: "tuist-project-2", account_id: account.id, token: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(ProjectChangeRemoteCacheStorageService::Error::S3BucketNotFound) do
      ProjectChangeRemoteCacheStorageService.call(id: "non-existent-id", project_id: project.id, user: user)
    end
  end
end
