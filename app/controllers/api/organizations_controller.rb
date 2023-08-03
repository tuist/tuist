# frozen_string_literal: true

module API
  # Controller for managing organizations
  class OrganizationsController < APIController
    def create
      organization = OrganizationCreateService.call(
        creator: current_user,
        name: params[:name]
      )

      render(json: organization)
    end
  end
end
