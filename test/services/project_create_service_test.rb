# frozen_string_literal: true

require "test_helper"

class ProjectCreateServiceTest < ActiveSupport::TestCase
  test "creates a project with a given account_id" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    project_name = "tuist"

    # When
    got = ProjectCreateService.call(creator: user, name: project_name, account_id: account.id)

    # Then
    assert_equal project_name, got.name
    assert_equal account, got.account
  end

  test "creates a project and a new organization" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    project_name = "tuist"
    organization_name = "tuist-org"
    organization = Organization.create!
    organization_account = Account.create!(owner: organization, name: organization_name)

    OrganizationCreateService.expects(:call).with(
      creator: user,
      name: organization_name
    ).returns(
      organization
    )

    # When
    got = ProjectCreateService.call(creator: user, name: project_name, organization_name: organization_name)

    # Then
    assert_equal project_name, got.name
    assert_equal organization_account, got.account
  end
end
