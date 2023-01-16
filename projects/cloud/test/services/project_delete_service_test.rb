# frozen_string_literal: true

require "test_helper"

class ProjectDeleteServicerviceTest < ActiveSupport::TestCase
  setup do
    client = Aws::S3::Client.new(stub_responses: true)
    Aws::S3::Client.stubs(:new).returns(client)
  end

  test "deletes a project and its default bucket with a given id" do
    # Given
    deleter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = deleter.account
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    s3_bucket = account.s3_buckets.create!(
      name: "test-tuist-project",
      access_key_id: "",
      secret_access_key: "",
      iv: "",
      region: "",
      is_default: true,
      default_project_id: project.id,
    )
    project.update(remote_cache_storage: s3_bucket)

    # When
    got = ProjectDeleteService.call(id: project.id, deleter: deleter)

    # Then
    assert_equal project, got
    assert_raises(ActiveRecord::RecordNotFound) do
      Project.find(project.id)
    end
    assert_nil S3Bucket.find_by(id: s3_bucket.id)
  end

  test "fails to fetch a project if deleter does not have rights to update it" do
    # Given
    deleter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    deleter.add_role(:user, organization)

    # When / Then
    assert_raises(ProjectDeleteService::Error::Unauthorized) do
      ProjectDeleteService.call(id: project.id, deleter: deleter)
    end
  end
end
