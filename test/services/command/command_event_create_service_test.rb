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
      project_slug: nil,
      user: nil,
      project: project,
      name: "fetch",
      subcommand: "",
      command_arguments: ["fetch", "--path", "./"],
      duration: 120,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0",
      cacheable_targets: nil,
      local_cache_target_hits: nil,
      remote_cache_target_hits: nil,
      is_ci: true,
    )

    # Then
    assert_equal project.command_events, [got]
    assert_nil got.cacheable_targets
    assert_nil got.local_cache_target_hits
    assert_nil got.remote_cache_target_hits
    assert_equal "fetch", got.name
    assert_equal true, got.is_ci
  end

  test "creates a cache warm command event for a given project" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))

    # When
    got = CommandEventCreateService.call(
      project_slug: "#{account.name}/#{project.name}",
      user: user,
      project: nil,
      name: "cache",
      subcommand: "warm",
      command_arguments: ["cache", "warm"],
      duration: 120,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0",
      cacheable_targets: ["Target1", "Target2", "Target3", "Target4"],
      local_cache_target_hits: ["Target1"],
      remote_cache_target_hits: ["Target2", "Target4"],
      is_ci: false,
    )

    # Then
    assert_equal project.command_events, [got]
    assert_equal "cache", got.name
    assert_equal "Target1;Target2;Target3;Target4", got.cacheable_targets
    assert_equal "Target1", got.local_cache_target_hits
    assert_equal "Target2;Target4", got.remote_cache_target_hits
    assert_equal false, got.is_ci
  end
end
