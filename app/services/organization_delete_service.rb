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
    organization = OrganizationFetchService.call(name: name, user: deleter)

    raise Error::Unauthorized.new unless OrganizationPolicy.new(deleter, organization).update?
    ActiveRecord::Base.transaction do
      subscription = Stripe::Subscription.list({
        limit: 1,
        customer: organization.account.customer_id,
      }).first
      if !subscription.nil?
        Stripe::Subscription.cancel(subscription.id)
      end
      organization.destroy
    end
  end
end
