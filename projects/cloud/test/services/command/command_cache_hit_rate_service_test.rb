# frozen_string_literal: true

require "test_helper"

class CommandCacheHitRateServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    @project = Project.create!(
      name: "my-project",
      account_id: @user.account.id,
      token: Devise.friendly_token.first(8),
    )
  end

  def create_command_event(cacheable_targets: nil, local_cache_target_hits: nil, remote_cache_target_hits: nil)
    CommandEvent.create!(
      name: "generate",
      subcommand: "",
      command_arguments: ["generate"],
      duration: 1,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0",
      project: @project,
      created_at: Time.new(2022, 03, 30),
      cacheable_targets: cacheable_targets,
      local_cache_target_hits: local_cache_target_hits,
      remote_cache_target_hits: remote_cache_target_hits,
    )
  end

  test "returns average cache hit rate when half of items is cached" do
    # Given
    command_event = create_command_event(
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "A",
      remote_cache_target_hits: "B",
    )

    # When
    got = CommandCacheHitRateService.call(command_event: command_event)

    # Then
    assert_equal 0.5, got
  end

  test "returns average cache hit rate when three quarters of items are cached" do
    # Given
    command_event = create_command_event(
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "A",
      remote_cache_target_hits: "B;C",
    )

    # When
    got = CommandCacheHitRateService.call(command_event: command_event)

    # Then
    assert_equal 0.75, got
  end

  test "returns nil when cacheable targets are not defined" do
    # Given
    command_event = create_command_event()

    # When
    got = CommandCacheHitRateService.call(command_event: command_event)

    # Then
    assert_nil got
  end
end
