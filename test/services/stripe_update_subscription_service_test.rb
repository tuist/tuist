# frozen_string_literal: true

require "test_helper"

class StripeUpdateSubscriptionServiceTest < ActiveSupport::TestCase
  Subscription = Struct.new(:customer, :status)
  test "updates to team plan when trialing" do
    # Given
    account = Account.create!(
      owner: Organization.create!,
      name: "tuist",
      customer_id: "1",
      plan: nil
    )

    # When
    StripeUpdateSubscriptionService.call(
      subscription: Subscription.new(
        customer: "1",
        status: "trialing"
      )
    )

    # Then
    assert_equal "team", Account.find(account.id).plan
  end

  test "updates to team plan when active" do
    # Given
    account = Account.create!(
      owner: Organization.create!,
      name: "tuist",
      customer_id: "1",
      plan: nil
    )

    # When
    StripeUpdateSubscriptionService.call(
      subscription: Subscription.new(
        customer: "1",
        status: "trialing"
      )
    )

    # Then
    assert_equal "team", Account.find(account.id).plan
  end

  test "resets plan when unpaid" do
    # Given
    account = Account.create!(
      owner: Organization.create!,
      name: "tuist",
      customer_id: "1",
      plan: :team
    )

    # When
    StripeUpdateSubscriptionService.call(
      subscription: Subscription.new(
        customer: "1",
        status: "trialing"
      )
    )

    # Then
    assert_equal "team", Account.find(account.id).plan
  end
end
