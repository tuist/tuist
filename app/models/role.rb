# frozen_string_literal: true

class Role < ApplicationRecord
  has_and_belongs_to_many :users, join_table: :users_roles

  after_create :add_seat, if: :stripe_configured?
  before_destroy :remove_seat, if: :stripe_configured?

  belongs_to :resource,
    polymorphic: true,
    optional: true

  validates :resource_type,
    inclusion: { in: Rolify.resource_types },
    allow_nil: true

  scopify

  def remove_seat
    StripeRemoveSeatService.call(organization: resource)
  end

  def add_seat
    StripeAddSeatService.call(organization: resource)
  end

  def stripe_configured?
    Environment.stripe_configured?
  end
end
