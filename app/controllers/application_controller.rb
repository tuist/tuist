# frozen_string_literal: true
# typed: strict

class ApplicationController < ActionController::Base
  extend T::Sig

  protect_from_forgery with: :null_session

  before_action :store_location
  before_action :authenticate_user!
  before_action :set_authenticated_user_projects
  before_action :redirect_if_needed
  before_action :set_account_and_project_names
  before_action :update_last_visited_project
  skip_before_action :authenticate_user!, if: :tuist_project?
  skip_before_action :authenticate_user!, only: :ready

  sig { void }
  def app
    project = T.must(current_user).last_visited_project || UserProjectsFetchService.call(user: current_user).first
    if project.nil?
      redirect_to("/get-started")
    else
      redirect_to("/#{project.account.name}/#{project.name}")
    end
  end

  # rubocop:disable Naming/AccessorMethodName
  sig { void }
  def get_started
    set_authenticated_user_organizations
    render('get_started')
  end
  # rubocop:enable Naming/AccessorMethodName

  sig { void }
  def ready
    head(:ok)
  end

  private

  sig { void }
  def store_location
    unless request.path.starts_with?('/user') ||
        request.path.starts_with?('/packs') ||
        request.path.starts_with?('/vite')
      store_location_for(:user, request.path)
    end
  end

  sig { void }
  def set_authenticated_user_organizations
    @current_organizations = T.let(
      if Environment.stripe_configured?
        UserOrganizationsFetchService.call(user: current_user)
      else
        []
      end,
      T.untyped,
    )
  end

  sig { void }
  def set_authenticated_user_projects
    unless current_user.nil?
      @projects = T.let(UserProjectsFetchService.call(user: current_user), T.untyped)
    end
  end

  sig { void }
  def redirect_if_needed
    if params[:redirect_to].present?
      redirect_to(params[:redirect_to])
    end
  end

  sig { void }
  def set_account_and_project_names
    if params[:account_name].present? && params[:project_name].present?
      @account_name = T.let(params[:account_name], T.nilable(String))
      @project_name = T.let(params[:project_name], T.nilable(String))
    end
  end

  sig do
    void
  end
  def update_last_visited_project
    if params[:account_name].present? && params[:project_name].present? && current_user.present?
      project = ProjectFetchService.new.fetch_by_name(
        name: params[:project_name],
        account_name: params[:account_name],
        subject: current_user,
      )
      LastVisitedProjectUpdateService.call(id: project.id, user: current_user)
    end
  end

  rescue_from(CloudError) do |error, _obj, _args, _ctx, _field|
    @error_message = T.let(error.message, T.nilable(String))
    render "error"
  end

  sig do
    returns(T::Boolean)
  end
  def tuist_project?
    params[:project_name] == "tuist" && params[:account_name] == "tuist"
  end
end
