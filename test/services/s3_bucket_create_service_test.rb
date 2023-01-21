# frozen_string_literal: true

require "test_helper"

class S3BucketCreateServiceTest < ActiveSupport::TestCase
  test "creates an S3 bucket" do
    # Given
    name = "bucket"
    access_key_id = "access key id"
    secret_access_key = "secret access key"
    region = "region"
    account = Account.create!(owner: Organization.create!, name: "tuist")

    # When
    got = S3BucketCreateService.call(
      name: name,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      account_id: account.id,
      region: region,
    )

    # Then
    assert_equal name, got.name
    assert_equal access_key_id, got.access_key_id
    assert_not_equal secret_access_key, got.secret_access_key
    assert_equal account.id, got.account_id
    assert_equal region, got.region
  end

  test "creates a default S3 bucket" do
    # Given
    name = "bucket"
    access_key_id = "access key id"
    secret_access_key = "secret access key"
    region = "region"
    account = Account.create!(owner: Organization.create!, name: "tuist")
    project = Project.create!(name: "tuist/tuist", account_id: account.id, token: Devise.friendly_token.first(8))

    # When
    got = S3BucketCreateService.call(
      name: name,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      account_id: account.id,
      region: region,
      default_project: project,
    )

    # Then
    assert_equal name, got.name
    assert_equal access_key_id, got.access_key_id
    assert_not_equal secret_access_key, got.secret_access_key
    assert_equal account.id, got.account_id
    assert_equal region, got.region
    assert_equal true, got.is_default
    assert_equal project.id, got.default_project_id
  end

  test "creating an S3 bucket fails when another with the same name already exists" do
    # Given
    account = Account.create!(owner: Organization.create!, name: "tuist")
    S3BucketCreateService.call(
      name: "bucket",
      access_key_id: "key id 1",
      secret_access_key: "secret access key",
      region: "region",
      account_id: account.id,
    )

    # When/Then
    assert_raises(S3BucketCreateService::Error::DuplicatedName) do
      S3BucketCreateService.call(
        name: "bucket",
        access_key_id: "key id 2",
        secret_access_key: "secret access key",
        region: "region",
        account_id: account.id,
      )
    end
  end
end
