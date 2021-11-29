# frozen_string_literal: true

require "test_helper"

class ChangeUserRoleServiceTest < ActiveSupport::TestCase
  test "change user's role from admin to user in the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:admin, organization)

    # When
    got = ChangeUserRoleService.call(
      user_id: user.id,
      organization_id: organization.id,
      current_role: :admin,
      new_role: :user
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

    # When
    got = ChangeUserRoleService.call(
      user_id: user.id,
      organization_id: organization.id,
      current_role: :user,
      new_role: :admin
    )

    # Then
    assert !got.has_role?(:user, organization)
    assert got.has_role?(:admin, organization)
  end
end
