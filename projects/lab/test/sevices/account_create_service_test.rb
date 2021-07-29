# frozen_string_literal: true
class AccountCreateServiceTest < ActiveSupport::TestCase
  test "creates the account when the owner is a organization" do
    # Given
    organization = Organization.create!

    # When
    account = AccountCreateService.call(owner: organization, name: "test-account")

    # Then
    assert_equal "test-account", account.name
    assert_equal organization, account.owner
  end
end
