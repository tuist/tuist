# frozen_string_literal: true

require "test_helper"

class OrganizationFetchServiceTest < ActiveSupport::TestCase
  test "fetches an organization with a given name" do
    # Given
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")

    # When
    got = OrganizationFetchService.call(name: account.name)

    # Then
    assert_equal organization, got
  end
end
