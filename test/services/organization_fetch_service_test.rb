# frozen_string_literal: true

require "test_helper"

class OrganizationFetchServiceTest < ActiveSupport::TestCase
  setup do
    StripeAddSeatService.stubs(:call)
  end

  test "fetches an organization with a given name" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    user.add_role(:user, organization)

    # When
    got = OrganizationFetchService.call(name: account.name, subject: user)

    # Then
    assert_equal organization, got
  end

  test "fails with organization not found if the organization does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(OrganizationFetchService::Error::OrganizationNotFound) do
      OrganizationFetchService.call(name: "non-existent-name", subject: user)
    end
  end

  test "fails with unauthorized error if the user does not have the rights to access the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")

    # When / Then
    assert_raises(OrganizationFetchService::Error::Unauthorized) do
      OrganizationFetchService.call(name: account.name, subject: user)
    end
  end
end
