# frozen_string_literal: true

class StripeCreateSessionService < ApplicationService
  module Error
    class StripeNotConfigured < CloudError
      def message
        "Billing dashboard is not available for this organization."
      end

      def status_code
        :bad_request
      end
    end
  end

  attr_reader :account_id, :organization_name, :user

  def initialize(account_id:, organization_name:, user:)
    super()
    @account_id = account_id
    @organization_name = organization_name
    @user = user
  end

  def call
    unless Environment.stripe_configured?
      raise Error::StripeNotConfigured
    end

    # rubocop:disable Style/ConditionalAssignment
    if account_id.nil?
      account_id = OrganizationFetchService.call(name: organization_name, user: user).account.id
    else
      account_id = @account_id
    end
    # rubocop:enable Style/ConditionalAssignment
    customer_id = Account.find(account_id).customer_id
    return_url = URI.parse(Environment.app_url).tap { |uri| uri.path = '/get-started' }.to_s
    Stripe::BillingPortal::Session.create({
      customer: customer_id,
      return_url: return_url,
    }).url
  end
end
