# frozen_string_literal: true

require "test_helper"

class StripeCreateSessionServiceTest < ActiveSupport::TestCase
  Session = Struct.new(:url)
  test "returns a Stripe URL session" do
    # Given
    account = Account.create!(owner: Organization.create!, name: "tuist", customer_id: "1")
    Stripe::BillingPortal::Session.expects(:create)
      .with() { |param| param[:customer] == "1" }
      .returns(Session.new(url: "some_url"))

    # When
    got = StripeCreateSessionService.call(
      account_id: account.id
    )

    # Then
    assert_equal "some_url" , got
  end
end
