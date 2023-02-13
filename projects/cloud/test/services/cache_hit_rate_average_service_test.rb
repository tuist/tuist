# frozen_string_literal: true

require "test_helper"

class CacheHitRateAverageServiceTest < ActiveSupport::TestCase
  setup do
    ENV["TZ"] = "UTC"
    @user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    @project = Project.create!(
      name: "my-project",
      account_id: @user.account.id,
      token: Devise.friendly_token.first(8),
    )
    ProjectFetchService.any_instance.stubs(:fetch_by_id).returns(@project)
    Time.stubs(:now).returns(Time.new(2022, 03, 31))
  end

  def create_command_event(
    name:,
    cacheable_targets: nil,
    local_cache_target_hits: nil,
    remote_cache_target_hits: nil,
    created_at:
  )
    CommandEvent.create!(
      name: name,
      subcommand: nil,
      command_arguments: [name],
      duration: 1,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0",
      cacheable_targets: cacheable_targets,
      local_cache_target_hits: local_cache_target_hits,
      remote_cache_target_hits: remote_cache_target_hits,
      project: @project,
      created_at: created_at,
    )
  end

  test "returns average for the last thirty days" do
    # Given
    create_command_event(
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "A",
      remote_cache_target_hits: "",
      created_at: Time.new(2022, 03, 30),
    )
    create_command_event(
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "A;B",
      remote_cache_target_hits: "C",
      created_at: Time.new(2022, 03, 30),
    )
    create_command_event(
      name: "generate",
      cacheable_targets: "",
      local_cache_target_hits: "",
      remote_cache_target_hits: "",
      created_at: Time.new(2022, 03, 30),
    )
    create_command_event(name: "fetch", created_at: Time.new(2022, 03, 30))
    create_command_event(name: "generate", created_at: Time.new(2022, 03, 05))

    # When
    got = CacheHitRateAverageService.call(project_id: @project.id, command_name: "generate", user: @user)

    # Then
    assert_equal (1..31).map { |day| Date.new(2022, 03, day) }, got.map(&:date)
    assert_equal (1..31).map { |day|
      if day == 30
        0.5
      else
        0
      end
    },
      got.map(&:cache_hit_rate_average)
  end
end
