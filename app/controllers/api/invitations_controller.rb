# frozen_string_literal: true

module API
  # Controller for managing invitations to an organization
  class InvitationsController < APIController
    authorize_current_subject_type create: [:user], destroy: [:user]

    def create
      organization = OrganizationFetchService.call(name: params[:organization_name], subject: current_subject)
      invitation = OrganizationInviteService.new.invite(
        inviter: current_user,
        invitee_email: params[:invitee_email],
        organization_id: organization.id,
      )

      render(json: invitation)
    end

    def destroy
      OrganizationInviteService.new.cancel_invite_by_email(
        invitee_email: params[:invitee_email],
        organization_name: params[:organization_name],
        remover: current_user,
      )

      head(:no_content)
    end
  end
end
