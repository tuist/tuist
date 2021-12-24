# frozen_string_literal: true

require "test_helper"

class UserOrganizationsFetchServiceTest < ActiveSupport::TestCase
  test "test returns user organizations" do
    # Given
    user = User.create!(
      email: "tuist@tuist.io",
      password: "my-password",
      confirmed_at: Date.new
    )
    organizations = [
      Organization.create!(),
      Organization.create!(),
      Organization.create!(),
    ]
    user.add_role(:user, organizations[0])
    user.add_role(:admin, organizations[2])

    # When
    gotOrganizations = UserOrganizationsFetchService.call(user: user)

    # Then
    assert_equal(
      gotOrganizations,
      [
        organizations[0],
        organizations[2],
      ]
    )
  end

  test "test returns no organizations" do
    # Given
    user = User.create!(
      email: "tuist@tuist.io",
      password: "my-password",
      confirmed_at: Date.new
    )
    [
      Organization.create!(),
      Organization.create!(),
      Organization.create!(),
    ]

    # When
    gotOrganizations = UserOrganizationsFetchService.call(user: user)

    # Then
    assert_empty(gotOrganizations)
  end
end
