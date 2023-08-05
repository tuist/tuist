# frozen_string_literal: true

class OrganizationInviteService < ApplicationService
  attr_reader :inviter, :invitee_email, :organization_id

  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to invite users to this organization."
      end

      def status_code
        :unauthorized
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

    class InvitationByInviteeEmailNotFound < CloudError
      attr_reader :invitee_email, :organization_name

      def initialize(invitee_email, organization_name)
        @invitee_email = invitee_email
        @organization_name = organization_name
      end

      def message
        "Invitation for #{invitee_email} to the #{organization_name} organization was not found."
      end

      def status_code
        :not_found
      end
    end

    class DuplicateInvitation < CloudError
      attr_reader :invitee_email, :organization_name

      def status_code
        :bad_request
      end

      def initialize(invitee_email, organization_name)
        @invitee_email = invitee_email
        @organization_name = organization_name
      end

      def message
        "User with email #{invitee_email} has already been invited to the #{organization_name} organization."
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
        token: invitation.token,
      )
      .deliver_now
    invitation
  end

  def cancel_invite_by_email(invitee_email:, organization_name:, remover:)
    organization = OrganizationFetchService.call(name: organization_name, user: remover)
    begin
      invitation = Invitation.find_by!(invitee_email: invitee_email, organization_id: organization.id)
    rescue ActiveRecord::RecordNotFound
      raise Error::InvitationByInviteeEmailNotFound.new(invitee_email, organization_name)
    end
    cancel_invite(invitation_id: invitation.id, remover: remover)
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
        token: token,
      )
    rescue ActiveRecord::RecordNotUnique
      raise Error::DuplicateInvitation.new(invitee_email, organization.name)
    end
    InvitationMailer
      .invitation_mail(
        inviter: inviter,
        invitee_email: invitee_email,
        organization: organization,
        token: token,
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
