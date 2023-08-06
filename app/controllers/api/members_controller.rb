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
  end
end
