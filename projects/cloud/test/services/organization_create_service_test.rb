# frozen_string_literal: true

require "test_helper"

class OrganizationCreateServiceTest < ActiveSupport::TestCase
  test "creates the organization and adds the creator as an admin" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization_name = "Tuist"

    # When
    got = OrganizationCreateService.call(
      creator: user,
      name: organization_name
    )

    # Then
    assert_equal organization_name, got.name
    assert user.has_role?(:admin, got)
  end

  test "the organization name is suffixed if an organization with the same name already exists" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization_name = "Tuist"

    # When
    OrganizationCreateService.call(
      creator: user,
      name: organization_name
    )
    got = OrganizationCreateService.call(
      creator: user,
      name: organization_name
    )

    # Then
    assert_equal organization_name + "1", got.name
    assert user.has_role?(:admin, got)
  end
end
