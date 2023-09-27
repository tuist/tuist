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
