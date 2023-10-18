# frozen_string_literal: true

module API
  # Controller for managing organizations
  class OrganizationsController < APIController
    authorize_current_subject_type create: [:user], index: [:user], destroy: [:user], show: [:user]

    def create
      organization = OrganizationCreateService.call(
        creator: current_user,
        name: params[:name],
      )

      render(json: organization)
    end

    def index
      organizations = UserOrganizationsFetchService.call(user: current_user)
      render(json: { organizations: organizations })
    end

    def destroy
      # The API route permits both organization name and ID. We currently handle the organization name only.
      OrganizationDeleteService.call(name: params[:id], deleter: current_user)
      head(:no_content)
    end

    def show
      organization = OrganizationFetchService.call(name: params[:id], subject: current_user)
      render(json: organization)
    end
  end
end
