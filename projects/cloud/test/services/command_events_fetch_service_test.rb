# frozen_string_literal: true

require "test_helper"

class CommandEventsFetchServiceTest < ActiveSupport::TestCase
  test "fetches command events tied to a given project" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    command_event_one = CommandEvent.create!(
      name: "fetch",
      subcommand: "",
      command_arguments: ["fetch", "--path", "./"],
      duration: 120,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0",
      project: project,
    )
    command_event_two = CommandEvent.create!(
      name: "generate",
      subcommand: "",
      command_arguments: ["generate"],
      duration: 40,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0",
      project: project,
    )

    # When
    got = CommandEventsFetchService.call(project_id: project.id, user: user)

    # Then
    assert_equal [command_event_two, command_event_one], got
  end
end
