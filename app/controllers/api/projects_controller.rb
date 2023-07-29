# frozen_string_literal: true

module API
  # Controller for managing projects
  class ProjectsController < APIController
    def index
      projects = UserProjectsFetchService.call(user: current_user)

      render(json: projects)
    end

    def create
      project = ProjectCreateService.call(
        creator: current_user,
        name: params[:name],
        organization_name: params[:organization]
      )

      render(json: project)
    end
  end
end
