# frozen_string_literal: true

class StripeUpdateSubscriptionService < ApplicationService
  attr_reader :subscription

  def initialize(subscription:)
    super()
    @subscription = subscription
  end

  def call
    account = Account.find_by!(customer_id: subscription.customer)
    if subscription.status == 'active' || subscription.status == 'trialing'
      account.update!(plan: :team)
    else
      account.update!(plan: nil)
    end
  end
end
