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
    @organizations = UserOrganizationsFetchService.call(user: current_user)
    render 'get_started'
  end

  def create_customer_portal_session
    # TODO: This should be moved to a service
    customer_id = Account.find(params[:account_id]).customer_id
    return_url = URI.parse(Environment.app_url).tap { |uri| uri.path = '/get-started' }.to_s
    session = Stripe::BillingPortal::Session.create({
      customer: customer_id,
      return_url: return_url,
    })
    redirect_to(session.url, allow_other_host: true)
  end

  private

  def setup_self_hosting
    @self_hosted = Environment.self_hosted?
  end
end
