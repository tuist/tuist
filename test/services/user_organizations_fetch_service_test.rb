# frozen_string_literal: true

require "test_helper"

class UserOrganizationsFetchServiceTest < ActiveSupport::TestCase
  setup do
    StripeAddSeatService.stubs(:call)
  end

  test "test returns user organizations" do
    # Given
    user = User.create!(
      email: "tuist@tuist.io",
      password: "my-password",
      confirmed_at: Date.new,
    )
    organizations = [
      Organization.create!,
      Organization.create!,
      Organization.create!,
    ]
    user.add_role(:user, organizations[0])
    user.add_role(:admin, organizations[2])

    # When
    got_organizations = UserOrganizationsFetchService.call(user: user)

    # Then
    assert_equal(
      got_organizations,
      [
        organizations[0],
        organizations[2],
      ],
    )
  end

  test "test returns no organizations" do
    # Given
    user = User.create!(
      email: "tuist@tuist.io",
      password: "my-password",
      confirmed_at: Date.new,
    )

    # When
    got_organizations = UserOrganizationsFetchService.call(user: user)

    # Then
    assert_empty(got_organizations)
  end
end
