# frozen_string_literal: true

class StripeRemoveSeatService < ApplicationService
  attr_reader :organization

  def initialize(organization:)
    super()
    @organization = organization
  end

  def call
    subscription = Stripe::Subscription.list({
      limit: 1,
      customer: organization.account.customer_id,
    }).first

    plan = subscription.items.data.first
    Stripe::SubscriptionItem.update(
      plan.id,
      {
        quantity: plan.quantity - 1,
      },
    )
  end
end
