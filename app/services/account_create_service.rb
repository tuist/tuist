# frozen_string_literal: true

class AccountCreateService < ApplicationService
  module Error
    class AccountAlreadyExists < CloudError
      attr_reader :account_name

      def initialize(account_name)
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
      raise Error::AccountAlreadyExists.new(name)
    end

    account = Account.create!(
      name: name,
      owner: owner,
    )

    if Environment.stripe_configured?
      customer = Stripe::Customer.create({
        name: name,
      })
      subscription = Stripe::Subscription.create({
        customer: customer.id,
        items: [
          {
            price: 'price_1NkZ69LWue9IBlPS0P60kMB8',
            quantity: 1,
          },
        ],
        trial_period_days: 14,
      })
      account.update(customer_id: customer.id)
    end

    account
  end
end
