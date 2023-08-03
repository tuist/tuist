# frozen_string_literal: true

module API
  # Controller for managing projects
  class ProjectsController < APIController
    def index
      projects = UserProjectsFetchService.call(
        user: current_user,
        account_name: params[:account_name],
        project_name: params[:project_name]
      )

      render(json: { projects: projects })
    end

    def create
      project = ProjectCreateService.call(
        creator: current_user,
        name: params[:name],
        organization_name: params[:organization]
      )

      render(json: project)
    end

    def destroy
      ProjectDeleteService.call(id: params[:id], deleter: current_user)
      head :no_content
    end
  end
end
