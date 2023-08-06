# frozen_string_literal: true

module API
  # Controller for managing members of an organization
  class MembersController < APIController
    def destroy
      RemoveMemberService.call(
        username: params[:username],
        organization_name: params[:organization_name],
        remover: current_user
      )
    end

    def update
      organization_member = ChangeMemberRoleService.call(
        username: params[:username],
        organization_name: params[:organization_name],
        role: params[:role],
        role_changer: current_user
      )

      render(json: organization_member.as_json)
    end
  end
end
