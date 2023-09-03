# frozen_string_literal: true

class Role < ApplicationRecord
  has_and_belongs_to_many :users, join_table: :users_roles # rubocop:disable Rails/HasAndBelongsToMany

  after_create :add_seat
  before_destroy :remove_seat

  belongs_to :resource,
    polymorphic: true,
    optional: true

  validates :resource_type,
    inclusion: { in: Rolify.resource_types },
    allow_nil: true

  scopify

  def remove_seat
    organization = resource
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

  def add_seat
    organization = resource
    subscription = Stripe::Subscription.list({
      limit: 1,
      customer: organization.account.customer_id,
    }).first

    if subscription.nil?
      Stripe::Subscription.create({
        customer: organization.customer.id,
        items: [
          {
            price: 'price_1NkZ69LWue9IBlPS0P60kMB8',
            quantity: 1,
          },
        ],
        trial_period_days: 14,
      })
    else
      plan = subscription.items.data.first
      Stripe::SubscriptionItem.update(
        plan.id,
        {
          quantity: plan.quantity + 1,
        },
      )
    end
  end
end
