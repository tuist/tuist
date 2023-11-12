# frozen_string_literal: true

require "test_helper"

class UserProjectsFetchServiceTest < ActiveSupport::TestCase
  test "returns all projects associated with a user" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    different_user = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    user.add_role(:user, organization)
    different_organization = Organization.create!
    Account.create!(owner: different_organization, name: "tuist-2")

    project_one = Project.create!(name: "project-one", account: user.account)
    project_two = Project.create!(name: "project-two", account: organization.account)
    Project.create!(name: "project-three", account: different_user.account)
    Project.create!(name: "project-four", account: different_organization.account)

    # When
    got = UserProjectsFetchService.call(user: user)

    # Then
    assert_equal 2, got.length
    assert_equal true, got.include?(project_one)
    assert_equal true, got.include?(project_two)
  end
end
