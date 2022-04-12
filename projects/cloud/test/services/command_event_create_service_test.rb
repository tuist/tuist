# frozen_string_literal: true

require "test_helper"

class CommandEventCreateServiceTest < ActiveSupport::TestCase
  test "creates a command event for a given project" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))

    # When
    got = CommandEventCreateService.call(
      project_slug: "#{account.name}/#{project.name}",
      user: user,
      name: "fetch",
      subcommand: "",
      command_arguments: ["fetch", "--path", "./"],
      duration: 120,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0"
    )

    # Then
    assert_equal project.command_events, [got]
    assert_equal "fetch", got.name
  end
end
