# frozen_string_literal: true

require "test_helper"

class RemoveUserServiceTest < ActiveSupport::TestCase
  test "remove user from the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:admin, organization)
    remover = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    remover.add_role(:admin, organization)

    # When
    got = RemoveUserService.call(
      user_id: user.id,
      organization_id: organization.id,
      remover: remover
    )

    # Then
    assert_not got.has_role?(:admin, organization)
    assert_not got.has_role?(:user, organization)
  end

  test "removing user from the organization if remover is not admin fails" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    user.add_role(:user, organization)
    remover = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    remover.add_role(:user, organization)

    # When / Then
    assert_raises(RemoveUserService::Error::Unauthorized) do
      RemoveUserService.call(
        user_id: user.id,
        organization_id: organization.id,
        remover: remover
      )
    end
  end

  test "user not found error is thrown when user with a given id does not exist" do
    # Given
    remover = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(RemoveUserService::Error::UserNotFound) do
      RemoveUserService.call(
        user_id: remover.id + 1,
        organization_id: 1,
        remover: remover
      )
    end
  end
end
