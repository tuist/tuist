# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

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

  def get_started
    @organizations = Environment.stripe_configured? ? UserOrganizationsFetchService.call(user: current_user) : []
    render 'get_started'
  end

  def create_customer_portal_session
    session_url = StripeCreateSessionService.call(account_id: params[:account_id])
    redirect_to(session_url, allow_other_host: true)
  end

  private

  def setup_self_hosting
    @self_hosted = Environment.self_hosted?
  end
end
