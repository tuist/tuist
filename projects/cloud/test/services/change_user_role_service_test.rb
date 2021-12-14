# frozen_string_literal: true

require "test_helper"

class ChangeUserRoleServiceTest < ActiveSupport::TestCase
  test "change user's role from admin to user in the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:admin, organization)
    role_changer = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    role_changer.add_role(:admin, organization)

    # When
    got = ChangeUserRoleService.call(
      user_id: user.id,
      organization_id: organization.id,
      role: :user,
      role_changer: role_changer
    )

    # Then
    assert_not got.has_role?(:admin, organization)
    assert got.has_role?(:user, organization)
  end

  test "change user's role from user to admin in the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:user, organization)
    role_changer = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    role_changer.add_role(:admin, organization)

    # When
    got = ChangeUserRoleService.call(
      user_id: user.id,
      organization_id: organization.id,
      role: :admin,
      role_changer: role_changer
    )

    # Then
    assert_not got.has_role?(:user, organization)
    assert got.has_role?(:admin, organization)
  end

  test "change user's role from user to admin in the organization if user is not admin fails" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:user, organization)
    role_changer = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    role_changer.add_role(:user, organization)

    # When / Then
    assert_raises(ChangeUserRoleService::Error::Unauthorized) do
      ChangeUserRoleService.call(
        user_id: user.id,
        organization_id: organization.id,
        role: :admin,
        role_changer: role_changer
      )
    end
  end

  test "user not found error is thrown when user with a given id does not exist" do
    # Given
    role_changer = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(ChangeUserRoleService::Error::UserNotFound) do
      ChangeUserRoleService.call(
        user_id: role_changer.id + 1,
        organization_id: 1,
        role: :admin,
        role_changer: role_changer
      )
    end
  end
end
