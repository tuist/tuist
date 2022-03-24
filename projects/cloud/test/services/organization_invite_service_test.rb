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
    got = OrganizationInviteService.new.invite(
      inviter: inviter,
      invitee_email: invitee_email,
      organization_id: organization.id
    )
    # Then
    assert_equal got.inviter, inviter
    assert_equal got.invitee_email, invitee_email
    assert_equal got.organization, organization
  end

  test "invite a user to two organizations" do
    # Given
    inviter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization_one = Organization.create!
    organization_two = Organization.create!
    Account.create!(owner: organization_one, name: "tuist_one")
    inviter.add_role(:admin, organization_one)
    Account.create!(owner: organization_two, name: "tuist_two")
    inviter.add_role(:admin, organization_two)
    invitee_email = "test1@cloud.tuist.io"

    # When
    OrganizationInviteService.new.invite(
      inviter: inviter,
      invitee_email: invitee_email,
      organization_id: organization_one.id
    )
    got = OrganizationInviteService.new.invite(
      inviter: inviter,
      invitee_email: invitee_email,
      organization_id: organization_two.id
    )
    # Then
    assert_equal got.inviter, inviter
    assert_equal got.invitee_email, invitee_email
    assert_equal got.organization, organization_two
  end

  test "inviting a user to the organization if user is not admin fails" do
    # Given
    inviter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    inviter.add_role(:user, organization)

    # When / Then
    assert_raises(OrganizationInviteService::Error::Unauthorized) do
      OrganizationInviteService.new.invite(
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
      OrganizationInviteService.new.invite(
        inviter: inviter,
        invitee_email: "test1@cloud.tuist.io",
        organization_id: "1"
      )
    end
  end

  test "inviting user to the same organization twice fails" do
    # Given
    inviter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    inviter.add_role(:admin, organization)
    invitee_email = "test1@cloud.tuist.io"

    # When / Then
    OrganizationInviteService.new.invite(
      inviter: inviter,
      invitee_email: invitee_email,
      organization_id: organization.id
    )
    assert_raises(OrganizationInviteService::Error::DuplicateInvitation) do
      OrganizationInviteService.new.invite(
        inviter: inviter,
        invitee_email: invitee_email,
        organization_id: organization.id
      )
    end
  end

  test "resend invitation" do
    # Given
    invitee_email = "test1@cloud.tuist.io"
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    inviter = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    inviter.add_role(:admin, organization)
    resender = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    resender.add_role(:admin, organization)
    invitation = inviter.invitations.create!(
      invitee_email: invitee_email,
      organization_id: organization.id,
      token: "token"
    )
    InvitationMailer.any_instance.expects(:invitation_mail).once

    # When
    got = OrganizationInviteService.new.resend_invite(
      invitation_id: invitation.id,
      resender: resender
    )

    # Then
    assert_equal got.inviter, inviter
    assert_equal got.invitee_email, invitee_email
    assert_equal got.organization, organization
  end

  test "resend invitation fails when not found" do
    # Given
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    resender = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    resender.add_role(:admin, organization)

    # When / Then
    assert_raises(OrganizationInviteService::Error::InvitationNotFound) do
      OrganizationInviteService.new.resend_invite(
        invitation_id: 0,
        resender: resender
      )
    end
  end

  test "cancel invitation" do
    # Given
    invitee_email = "test1@cloud.tuist.io"
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    remover = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    remover.add_role(:admin, organization)
    invitation = remover.invitations.create!(
      invitee_email: invitee_email,
      organization_id: organization.id,
      token: "token"
    )

    # When
    got = OrganizationInviteService.new.cancel_invite(
      invitation_id: invitation.id,
      remover: remover
    )

    # Then
    assert_equal got.inviter, remover
    assert_equal got.invitee_email, invitee_email
    assert_equal got.organization, organization
  end

  test "cancel invitation when invitation does not exist" do
    # Given
    organization = Organization.create!
    Account.create!(owner: organization, name: "tuist")
    remover = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    remover.add_role(:admin, organization)

    # When / Then
    assert_raises(OrganizationInviteService::Error::InvitationNotFound) do
      OrganizationInviteService.new.cancel_invite(
        invitation_id: 0,
        remover: remover
      )
    end
  end
end
