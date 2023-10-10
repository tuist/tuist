# frozen_string_literal: true

require "test_helper"

class TargetCacheHitRateServiceTest < ActiveSupport::TestCase
  setup do
    ENV["TZ"] = "UTC"
    @user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    @project = Project.create!(
      name: "my-project",
      account_id: @user.account.id,
      token: Devise.friendly_token.first(8),
    )
    ProjectFetchService.any_instance.stubs(:fetch_by_id).returns(@project)
    Time.stubs(:now).returns(Time.new(2022, 0o3, 31))
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

  test "returns target hit rates for the last thirty days" do
    # Given
    create_command_event(
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "A",
      remote_cache_target_hits: "",
      created_at: Time.new(2022, 0o3, 30),
    )
    create_command_event(
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "A;B",
      remote_cache_target_hits: "C",
      created_at: Time.new(2022, 0o3, 30),
    )
    create_command_event(
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "",
      remote_cache_target_hits: "",
      created_at: Time.new(2022, 0o3, 30),
    )
    create_command_event(
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "",
      remote_cache_target_hits: "A",
      created_at: Time.new(2022, 0o3, 30),
    )

    # When
    got = TargetCacheHitRateService.call(project_id: @project.id, user: @user)

    # Then
    assert_equal 4, got.length
    assert_equal ["A", "B", "C", "D"], got.map(&:target)
    assert_equal [0.75, 0.25, 0.25, 0.0], got.map(&:cache_hit_rate)
    assert_equal [3, 1, 1, 0], got.map(&:hits)
    assert_equal [1, 3, 3, 4], got.map(&:misses)
  end
end
