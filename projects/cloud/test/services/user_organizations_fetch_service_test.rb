# frozen_string_literal: true

require "test_helper"

class UserOrganizationsFetchServiceTest < ActiveSupport::TestCase
  def test_returns_user_organizations
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
    user.add_role(:user, organizations[2])

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

  def test_returns_no_organizations
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

    # When
    gotOrganizations = UserOrganizationsFetchService.call(user: user)

    # Then
    assert_empty(gotOrganizations)
  end

end
