# frozen_string_literal: true

require "test_helper"

class ChangeUserRoleServiceTest < ActiveSupport::TestCase
  test "change user's role from admin to user in the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:admin, organization)
    current_user = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    current_user.add_role(:admin, organization)

    # When
    got = ChangeUserRoleService.call(
      user_id: user.id,
      organization_id: organization.id,
      role: :user,
      acting_user: current_user
    )

    # Then
    assert !got.has_role?(:admin, organization)
    assert got.has_role?(:user, organization)
  end

  test "change user's role from user to admin in the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:user, organization)
    current_user = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    current_user.add_role(:admin, organization)

    # When
    got = ChangeUserRoleService.call(
      user_id: user.id,
      organization_id: organization.id,
      role: :admin,
      acting_user: current_user
    )

    # Then
    assert !got.has_role?(:user, organization)
    assert got.has_role?(:admin, organization)
  end

  test "change user's role from user to admin in the organization if user is not admin fails" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:user, organization)
    current_user = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    current_user.add_role(:user, organization)

    # When / Then
    assert_raises(ChangeUserRoleService::Error::Unauthorized) do
      ChangeUserRoleService.call(
        user_id: user.id,
        organization_id: organization.id,
        role: :admin,
        acting_user: current_user
      )
    end
  end
end
