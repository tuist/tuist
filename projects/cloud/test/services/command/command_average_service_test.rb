# frozen_string_literal: true

require "test_helper"

class CommandAverageServiceTest < ActiveSupport::TestCase
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

  def create_command_event(name:, subcommand: nil, duration:, created_at:)
    CommandEvent.create!(
      name: name,
      subcommand: subcommand,
      command_arguments: [name],
      duration: duration,
      client_id: "client id",
      tuist_version: "3.1.0",
      swift_version: "5.5.0",
      macos_version: "12.1.0",
      project: @project,
      created_at: created_at,
    )
  end

  test "returns average for the last thirty days" do
    # Given
    create_command_event(name: "generate", duration: 20, created_at: Time.new(2022, 03, 30))
    create_command_event(name: "generate", duration: 10, created_at: Time.new(2022, 03, 30))
    create_command_event(name: "fetch", duration: 10, created_at: Time.new(2022, 03, 30))
    create_command_event(name: "generate", duration: 5, created_at: Time.new(2022, 03, 05))

    # When
    got = CommandAverageService.call(project_id: @project.id, command_name: "generate", user: @user)

    # Then
    assert_equal (1..31).map { |day| Date.new(2022, 03, day) }, got.map(&:date)
    assert_equal (1..31).map { |day|
      if day == 05
        5
      elsif day == 30
        15
      else
        0
      end
    },
      got.map(&:duration_average)
  end

  test "returns average for the last thirty days for a subcommand" do
    # Given
    create_command_event(name: "cache", subcommand: "warm", duration: 20, created_at: Time.new(2022, 03, 30))
    create_command_event(name: "cache", subcommand: "warm", duration: 10, created_at: Time.new(2022, 03, 30))
    create_command_event(name: "cache", subcommand: "print-hashes", duration: 5, created_at: Time.new(2022, 03, 30))
    create_command_event(name: "fetch", duration: 10, created_at: Time.new(2022, 03, 30))
    create_command_event(name: "cache", subcommand: "print-hashes", duration: 5, created_at: Time.new(2022, 03, 05))

    # When
    got = CommandAverageService.call(
      project_id: @project.id,
      command_name: "cache warm",
      user: @user,
    )

    # Then
    assert_equal (1..31).map { |day| Date.new(2022, 03, day) }, got.map(&:date)
    assert_equal (1..31).map { |day|
      if day == 30
        15
      else
        0
      end
    },
      got.map(&:duration_average)
  end
end
