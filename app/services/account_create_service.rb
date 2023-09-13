# frozen_string_literal: true

class AccountCreateService < ApplicationService
  module Error
    class AccountAlreadyExists < CloudError
      attr_reader :account_name

      def initialize(account_name)
        super
        @account_name = account_name
      end

      def status_code
        :bad_request
      end

      def message
        "Account #{account_name} already exists. Choose a different name."
      end
    end
  end

  attr_reader :name, :owner

  def initialize(name:, owner:)
    @name = name
    @owner = owner
    super()
  end

  def call
    if Account.exists?(name: name)
      raise Error::AccountAlreadyExists, name
    end

    ActiveRecord::Base.transaction do
      account = Account.create!(
        name: name,
        owner: owner,
      )

      if Environment.stripe_configured?
        customer = Stripe::Customer.create({
          name: name,
        })
        if owner.is_a?(Organization)
          Stripe::Subscription.create({
            customer: customer.id,
            items: [
              {
                price: Environment.stripe_plan_id,
                quantity: 1,
              },
            ],
            trial_period_days: 14,
          })
          account.update(customer_id: customer.id, plan: :team)
        else
          account.update(customer_id: customer.id, plan: :personal)
        end
      end
      account
    end
  end
end
