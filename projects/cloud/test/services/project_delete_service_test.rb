# frozen_string_literal: true

require "test_helper"

class ProjectDeleteServicerviceTest < ActiveSupport::TestCase
  test "deletes a project with a given id" do
    # Given
    deleter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = deleter.account
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))

    # When
    got = ProjectDeleteService.call(id: project.id, deleter: deleter)

    # Then
    assert_equal project, got
    assert_raises(ActiveRecord::RecordNotFound) do
      Project.find(project.id)
    end
  end

  test "fails to fetch a project if deleter does not have rights to update it" do
    # Given
    deleter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(ProjectDeleteService::Error::Unauthorized) do
      ProjectDeleteService.call(id: project.id, deleter: deleter)
    end
  end

  test "fails with project not found if the project does not exist" do
    # Given
    deleter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(ProjectDeleteService::Error::ProjectNotFound) do
      ProjectDeleteService.call(id: 2, deleter: deleter)
    end
  end
end
