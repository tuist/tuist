# frozen_string_literal: true

require "test_helper"

class OrganizationCreateServiceTest < ActiveSupport::TestCase
  Customer = Struct.new(:id)

  test "creates the organization and adds the creator as an admin" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization_name = "Tuist"

    # When
    got = OrganizationCreateService.call(
      creator: user,
      name: organization_name,
    )

    # Then
    assert_equal organization_name, got.name
    assert user.has_role?(:admin, got)
  end

  test "creating organization fails when the organization already exists" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization_name = "Tuist"

    OrganizationCreateService.call(
      creator: user,
      name: organization_name,
    )

    # When / Then
    assert_raises(AccountCreateService::Error::AccountAlreadyExists) do
      OrganizationCreateService.call(
        creator: user,
        name: organization_name,
      )
    end
  end
end
