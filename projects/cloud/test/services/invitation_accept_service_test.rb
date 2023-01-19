# frozen_string_literal: true

require "test_helper"

class InvitationAcceptServiceTest < ActiveSupport::TestCase
  test "user accepts an invitation" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    inviter = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    token = Devise.friendly_token.first(8)
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    invitation = inviter.invitations.create!(invitee_email: user.email, token: token, organization: organization)

    # When
    got = InvitationAcceptService.call(token: token, user: user)

    # Then
    assert user.has_role?(:user, organization)
    assert organization, got
    assert_raises(ActiveRecord::RecordNotFound) do
      Invitation.find(invitation.id)
    end
  end

  test "fails with not authorized error when invitation email and user email mismatch" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    inviter = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    token = Devise.friendly_token.first(8)
    organization = Organization.create!
    inviter.invitations.create!(
      invitee_email: "test2@cloud.tuist.io",
      token: token,
      organization: organization)

    # When / Then
    assert_raises(InvitationAcceptService::Error::Unauthorized) do
      InvitationAcceptService.call(token: token, user: user)
    end
  end
end
