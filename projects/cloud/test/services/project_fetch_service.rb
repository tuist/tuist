# frozen_string_literal: true

require "test_helper"

class ProjectCreateServiceTest < ActiveSupport::TestCase
  test "fetches a project with a given name account_name" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = Account.create!(owner: user, name: "tuist")
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))

    # When
    got = ProjectFetchService.call(name: project.name, account_name: account.name)

    # Then
    assert_equal project, got
  end
end
