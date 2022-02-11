# frozen_string_literal: true

require "test_helper"

class AccountFetchServiceTest < ActiveSupport::TestCase
  test "returns account with the given name" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When
    got = AccountFetchService.call(name: "test")

    # Then
    assert_equal got, user.account
  end

  test "fails with account not found if the account does not exist" do
    # Given
    User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(AccountFetchService::Error::AccountNotFound) do
      AccountFetchService.call(name: "non-existent-name")
    end
  end
end
