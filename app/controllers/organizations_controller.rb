# frozen_string_literal: true

class OrganizationsController < ApplicationController
  def billing_plan
    session_url = StripeCreateSessionService.call(
      account_id: params[:account_id],
      organization_name: params[:organization_name],
      user: current_user,
    )
    redirect_to(session_url, allow_other_host: true)
  end

  def index
    @current_organizations = UserOrganizationsFetchService.call(user: current_user)

    render('organizations/index')
  end
end
