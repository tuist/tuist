# frozen_string_literal: true

class StripeSessionService < ApplicationService
  attr_reader :account_id

  def initialize(account_id:)
    super()
    @account_id = account_id
  end

  def call
    customer_id = Account.find(account_id).customer_id
    return_url = URI.parse(Environment.app_url).tap { |uri| uri.path = '/get-started' }.to_s
    Stripe::BillingPortal::Session.create({
      customer: customer_id,
      return_url: return_url,
    }).url
  end
end
