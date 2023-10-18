# frozen_string_literal: true

class OrganizationDeleteService < ApplicationService
  module Error
    class Unauthorized < CloudError
      def status_code
        :unauthorized
      end

      def message
        "You do not have a permission to delete this organization."
      end
    end
  end

  attr_reader :name, :deleter

  def initialize(name:, deleter:)
    super()
    @name = name
    @deleter = deleter
  end

  def call
    organization = OrganizationFetchService.call(name: name, subject: deleter)

    raise Error::Unauthorized unless OrganizationPolicy.new(deleter, organization).update?

    ActiveRecord::Base.transaction do
      customer_id = organization.account.customer_id
      organization.destroy
      if Environment.stripe_configured?
        subscription = Stripe::Subscription.list({
          limit: 1,
          customer: customer_id,
        }).first
        unless subscription.nil?
          Stripe::Subscription.cancel(subscription.id)
        end
      end
    end
  end
end
