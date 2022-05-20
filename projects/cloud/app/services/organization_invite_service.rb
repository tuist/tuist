# frozen_string_literal: true

class OrganizationInviteService < ApplicationService
  attr_reader :inviter, :invitee_email, :organization_id

  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to invite users to this organization."
      end
    end

    class OrganizationNotFound < CloudError
      attr_reader :organization_id

      def initialize(organization_id)
        @organization_id = organization_id
      end

      def message
        "Organization with id #{organization_id} was not found"
      end
    end

    class InvitationNotFound < CloudError
      attr_reader :invitation_id

      def initialize(invitation_id)
        @invitation_id = invitation_id
      end

      def message
        "Invitation with id #{invitation_id} was not found"
      end
    end

    class DuplicateInvitation < CloudError
      attr_reader :invitee_email, :organization_id

      def initialize(invitee_email, organization_id)
        @invitee_email = invitee_email
        @organization_id = organization_id
      end

      def message
        "User with email #{invitee_email} has already been to organization with id #{organization_id}. \
        Consider resending the invite instead."
      end
    end
  end

  def resend_invite(invitation_id:, resender:)
    invitation = find_invitation(invitation_id)
    organization = find_organization(invitation.organization.id)
    raise Error::Unauthorized unless OrganizationPolicy.new(resender, organization).update?

    InvitationMailer
      .invitation_mail(
        inviter: invitation.inviter,
        invitee_email: invitation.invitee_email,
        organization: organization,
        token: invitation.token
      )
      .deliver_now
    invitation
  end

  def cancel_invite(invitation_id:, remover:)
    invitation = find_invitation(invitation_id)
    organization = find_organization(invitation.organization_id)
    raise Error::Unauthorized unless OrganizationPolicy.new(remover, organization).update?

    invitation.delete
  end

  def invite(inviter:, invitee_email:, organization_id:)
    organization = find_organization(organization_id)
    raise Error::Unauthorized unless OrganizationPolicy.new(inviter, organization).update?

    token = Devise.friendly_token.first(16)
    begin
      invitation = inviter.invitations.create!(
        invitee_email: invitee_email,
        organization_id: organization.id,
        token: token
      )
    rescue ActiveRecord::RecordNotUnique
      raise Error::DuplicateInvitation.new(invitee_email, organization.id)
    end
    InvitationMailer
      .invitation_mail(
        inviter: inviter,
        invitee_email: invitee_email,
        organization: organization,
        token: token
      )
      .deliver_now
    invitation
  end

  private def find_invitation(invitation_id)
    begin
      invitation = Invitation.find(invitation_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::InvitationNotFound.new(invitation_id)
    end
    invitation
  end

  private def find_organization(organization_id)
    begin
      organization = Organization.find(organization_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::OrganizationNotFound.new(organization_id)
    end
    organization
  end
end
