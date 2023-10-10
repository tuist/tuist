# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  before_action :store_location
  before_action :authenticate_user!
  before_action :setup_self_hosting

  protect_from_forgery with: :null_session

  def app
    if current_user.legacy?
      render(layout: 'app')
    else
      get_started
    end
  end

  # rubocop:disable Naming/AccessorMethodName
  def get_started
    fetch_authenticated_user_organizations
    render('get_started')
  end
  # rubocop:enable Naming/AccessorMethodName

  def create_customer_portal_session
    session_url = StripeCreateSessionService.call(
      account_id: params[:account_id],
      organization_name: params[:organization_name],
      user: current_user,
    )
    redirect_to(session_url, allow_other_host: true)
  end

  def analytics
    project_id = ProjectFetchService.new.fetch_by_name(
      name: params[:project_name],
      account_name: params[:account_name],
      user: current_user,
    ).id
    @commands_average_duration = {
      generate: CommandAverageService.call(
        project_id: project_id,
        command_name: "generate",
        user: current_user,
      ),
      cache_warm: CommandAverageService.call(
        project_id: project_id,
        command_name: "cache warm",
        user: current_user,
      ),
      build: CommandAverageService.call(
        project_id: project_id,
        command_name: "build",
        user: current_user,
      ),
      test: CommandAverageService.call(
        project_id: project_id,
        command_name: "test",
        user: current_user,
      ),
    }

    @commands_average_cache_hit_rate = {
      generate: CacheHitRateAverageService.call(
        project_id: project_id,
        command_name: "generate",
        user: current_user,
      ),
      cache_warm: CacheHitRateAverageService.call(
        project_id: project_id,
        command_name: "cache warm",
        user: current_user,
      ),
    }

    @targets_cache_hit_rate = TargetCacheHitRateService.call(
      project_id: project_id,
      user: current_user,
    )
    render('analytics')
  end

  def analytics_modules
    project_id = ProjectFetchService.new.fetch_by_name(
      name: params[:project_name],
      account_name: params[:account_name],
      user: current_user,
    ).id
    @targets_cache_hit_rate = TargetCacheHitRateService.call(
      project_id: project_id,
      user: current_user,
    )

    unless params[:sort].nil?
      @targets_cache_hit_rate = @targets_cache_hit_rate
        .sort_by { |target| target.send(params[:sort]) }
    end
    render('analytics_modules')
  end

  private

  def store_location
    unless request.fullpath.starts_with?('/user') || request.fullpath.starts_with?('/packs')
      store_location_for(:user, request.fullpath)
    end
  end

  def setup_self_hosting
    @self_hosted = Environment.self_hosted?
  end

  def fetch_authenticated_user_organizations
    @current_organizations = if Environment.stripe_configured?
      UserOrganizationsFetchService.call(user: current_user)
    else
      []
    end
  end

  rescue_from(CloudError) do |error, _obj, _args, _ctx, _field|
    @error_message = error.message
    render "error"
  end
end
