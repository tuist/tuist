# frozen_string_literal: true

require "test_helper"

class CommandEventFetchServiceTest < ActiveSupport::TestCase
  test "fetches a command event with a given id" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    command_event = CommandEvent.create!(
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

    # When
    got = CommandEventFetchService.call(command_event_id: command_event.id, user: user)

    # Then
    assert_equal command_event, got
  end

  test "raises a not found error when command event does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(CommandEventFetchService::Error::CommandEventNotFound) do
      CommandEventFetchService.call(command_event_id: 1, user: user)
    end
  end

  test "fails to fetch a command event if the user does not have rights to access it" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    project = Project.create!(name: "tuist-project-2", account_id: account.id, token: Devise.friendly_token.first(16))
    command_event = CommandEvent.create!(
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

    # When / Then
    assert_raises(CommandEventFetchService::Error::Unauthorized) do
      CommandEventFetchService.call(command_event_id: command_event.id, user: user)
    end
  end
end
