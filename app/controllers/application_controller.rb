# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :null_session

  before_action :store_location
  before_action :authenticate_user!
  before_action :fetch_projects
  before_action :redirect_if_needed
  before_action :selected_project
  before_action :update_last_visited_project

  def app
    project = current_user.last_visited_project || UserProjectsFetchService.call(user: current_user).first
    if project.nil?
      redirect_to("/get-started")
    else
      redirect_to("/#{project.account.name}/#{project.name}")
    end
  end

  # rubocop:disable Naming/AccessorMethodName
  def get_started
    fetch_authenticated_user_organizations
    render('get_started')
  end
  # rubocop:enable Naming/AccessorMethodName

  private

  def store_location
    unless request.fullpath.starts_with?('/user') || request.fullpath.starts_with?('/packs')
      store_location_for(:user, request.fullpath)
    end
  end

  def fetch_authenticated_user_organizations
    @current_organizations = if Environment.stripe_configured?
      UserOrganizationsFetchService.call(user: current_user)
    else
      []
    end
  end

  def fetch_projects
    unless current_user.nil?
      @projects = UserProjectsFetchService.call(user: current_user)
    end
  end

  def redirect_if_needed
    if params[:redirect_to].present?
      redirect_to(params[:redirect_to])
    end
  end

  def selected_project
    if params[:account_name].present? && params[:project_name].present?
      @account_name = params[:account_name]
      @project_name = params[:project_name]
    end
  end

  def update_last_visited_project
    if params[:account_name].present? && params[:project_name].present?
      project = ProjectFetchService.new.fetch_by_name(
        name: params[:project_name],
        account_name: params[:account_name],
        subject: current_user,
      )
      LastVisitedProjectUpdateService.call(id: project.id, user: current_user)
    end
  end

  rescue_from(CloudError) do |error, _obj, _args, _ctx, _field|
    @error_message = error.message
    render "error"
  end
end
