# frozen_string_literal: true

require "test_helper"

class InvitationFetchServiceTest < ActiveSupport::TestCase
  test "fetches an invitation" do
    # Given
    inviter = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    token = Devise.friendly_token.first(8)
    organization = Organization.create!
    invitation = inviter.invitations.create!(
      invitee_email: "test@cloud.tuist.io",
      token: token,
      organization: organization)

    # When
    got = InvitationFetchService.call(token: token)

    # Then
    assert_equal invitation, got
  end

  test "fails with invitation not found if the invitation does not exist" do
    # Given
    token = Devise.friendly_token.first(8)

    # When / Then
    assert_raises(InvitationFetchService::Error::InvitationNotFound) do
      InvitationFetchService.call(token: token)
    end
  end
end
