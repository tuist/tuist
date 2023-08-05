# frozen_string_literal: true

module API
  # Controller for managing invitations to an organization
  class InvitationsController < APIController
    def create
      organization = OrganizationFetchService.call(name: params[:organization_name], user: current_user)
      invitation = OrganizationInviteService.new.invite(
        inviter: current_user,
        invitee_email: params[:invitee_email],
        organization_id: organization.id
      )

      render(json: invitation)
    end
  end
end
