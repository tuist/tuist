# frozen_string_literal: true

require "test_helper"

class OrganizationDeleteServiceTest < ActiveSupport::TestCase
  test "deletes an organization with a given name" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    user.add_role(:admin, organization)

    # When
    OrganizationDeleteService.call(name: account.name, deleter: user)

    # Then
    assert_nil Organization.find_by(id: organization.id)
  end

  test "fails with unauthorized error if the user does not have the rights to delete the organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    user.add_role(:user, organization)

    # When / Then
    assert_raises(OrganizationDeleteService::Error::Unauthorized) do
      OrganizationDeleteService.call(name: account.name, deleter: user)
    end
  end
end
