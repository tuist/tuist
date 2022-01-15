# frozen_string_literal: true

require "test_helper"

class OrganizationInviteServiceTest < ActiveSupport::TestCase
  test "invite a user to an organization" do
    # Given
    inviter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    inviter.add_role(:admin, organization)
    invitee_email = "test1@cloud.tuist.io"

    # When
    got = OrganizationInviteService.call(
      inviter: inviter,
      invitee_email: invitee_email,
      organization_id: organization.id
    )
    # Then
    assert_equal got.inviter, inviter
    assert_equal got.invitee_email, invitee_email
    assert_equal got.organization, organization
  end

  test "inviting a user to the organization if user is not admin fails" do
    # Given
    inviter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    inviter.add_role(:user, organization)

    # When / Then
    assert_raises(OrganizationInviteService::Error::Unauthorized) do
      OrganizationInviteService.call(
        inviter: inviter,
        invitee_email: "test1@cloud.tuist.io",
        organization_id: organization.id
      )
    end
  end

  test "organization not found error is thrown when organization with a given id does not exist" do
    # Given
    inviter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(OrganizationInviteService::Error::OrganizationNotFound) do
      OrganizationInviteService.call(
        inviter: inviter,
        invitee_email: "test1@cloud.tuist.io",
        organization_id: "1"
      )
    end
  end
end
