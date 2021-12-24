# frozen_string_literal: true

require "test_helper"

class UserAccountsFetchServiceTest < ActiveSupport::TestCase
  def test_returns_user_accounts
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
    organization_accounts = [
      Account.create!(name: "organization-0", owner: organizations[0]),
      Account.create!(name: "organization-1", owner: organizations[1]),
      Account.create!(name: "organization-2", owner: organizations[2]),
    ]

    UserOrganizationsFetchService.stubs(:call).returns(
      [
        organizations[0],
        organizations[2],
      ]
    )

    # When
    gotAccounts = UserAccountsFetchService.call(user: user)

    # Then
    assert_equal(
      gotAccounts,
      [
        user.account,
        organization_accounts[0],
        organization_accounts[2],
      ]
    )
  end

  def test_returns_user_account_only
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
    [
      Account.create!(name: "organization-0", owner: organizations[0]),
      Account.create!(name: "organization-1", owner: organizations[1]),
      Account.create!(name: "organization-2", owner: organizations[2]),
    ]

    UserOrganizationsFetchService.stubs(:call).returns([])

    # When
    gotAccounts = UserAccountsFetchService.call(user: user)

    # Then
    assert_equal(gotAccounts, [user.account])
  end
end
