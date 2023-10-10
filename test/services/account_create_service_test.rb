# frozen_string_literal: true

require "test_helper"

class AccountCreateServiceTest < ActiveSupport::TestCase
  Customer = Struct.new(:id)
  def test_create_an_account
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    Stripe::Customer.expects(:create)
      .with { |param| param[:name] == "tuist" }
      .returns(Customer.new(id: "1"))

    # When
    account = AccountCreateService.call(name: "tuist", owner: user.account)

    # Then
    assert_equal("tuist", account.name)
    assert_nil(account.plan)
    assert_equal("1", account.customer_id)
  end

  test "create an organization" do
    # Given
    organization = Organization.create!
    Stripe::Customer.expects(:create)
      .with { |param| param[:name] == "tuist" }
      .returns(Customer.new(id: "1"))

    Stripe::Subscription.expects(:create)
      .with { |param| param[:customer] == "1" && param[:items][0][:quantity] == 0 }

    # When
    account = AccountCreateService.call(name: "tuist", owner: organization)

    # Then
    assert_equal "tuist", account.name
    assert_equal "team", account.plan
    assert_equal "1", account.customer_id
  end

  def test_raises_an_error_when_account_already_exists
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    Stripe::Customer.stubs(:create).returns(Customer.new(id: "1"))
    AccountCreateService.call(name: "tuist", owner: user.account)

    # When / Then
    assert_raises(AccountCreateService::Error::AccountAlreadyExists) do
      AccountCreateService.call(name: "tuist", owner: user.account)
    end
  end
end
