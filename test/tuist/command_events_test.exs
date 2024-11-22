defmodule Tuist.CommandEventsTest do
  alias Tuist.PreviewsFixtures
  alias Tuist.CommandEvents.TestCaseRun
  alias Tuist.CommandEvents.TestCase
  alias Tuist.CommandEvents.TargetTestSummary
  alias Tuist.CommandEvents.ResultBundle.ActionTestMetadata
  alias Tuist.CommandEvents.TestSummary
  alias Tuist.CommandEventsFixtures
  alias Tuist.Storage
  alias Tuist.AccountsFixtures
  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias Tuist.CommandEventsFixtures
  alias Tuist.ProjectsFixtures
  alias Tuist.Time
  use Tuist.DataCase
  use Mimic

  describe "create_command_event/1" do
    test "truncates an error message if it's over 255 chars" do
      # Given
      error_message = String.duplicate("a", 300)

      # When
      command_event =
        CommandEventsFixtures.command_event_fixture(error_message: error_message)

      # Then
      assert String.length(command_event.error_message) == 255
    end

    test "does not truncate an error message if it's under 255 chars" do
      # Given
      error_message = String.duplicate("a", 200)

      # When
      command_event =
        CommandEventsFixtures.command_event_fixture(error_message: error_message)

      # Then
      assert String.length(command_event.error_message) == 200
      assert command_event.error_message == error_message
    end

    test "sends telemetry events" do
      # Given
      run_create_ref =
        :telemetry_test.attach_event_handlers(self(), [
          Tuist.Telemetry.event_name_run_command()
        ])

      cache_event_ref =
        :telemetry_test.attach_event_handlers(self(), [Tuist.Telemetry.event_name_cache()])

      # When
      command_event =
        CommandEvents.create_command_event(%{
          name: "generate",
          subcommand: "",
          command_arguments: [],
          duration: 100,
          tuist_version: "4.1.0",
          swift_version: "5.2",
          macos_version: "10.15",
          project_id: 1,
          cacheable_targets: ["A", "B", "C", "D"],
          local_cache_target_hits: ["A"],
          remote_cache_target_hits: ["B", "C"],
          test_targets: [],
          local_test_target_hits: [],
          remote_test_target_hits: [],
          is_ci: false,
          user_id: 1,
          client_id: "client-id",
          status: :success,
          preview_id: nil,
          git_ref: nil,
          git_commit_sha: nil,
          git_branch: nil,
          error_message: nil
        })

      # Then
      event_name_run_command = Tuist.Telemetry.event_name_run_command()
      event_name_cache = Tuist.Telemetry.event_name_cache()

      assert_received {^event_name_run_command, ^run_create_ref, %{duration: 100},
                       %{command_event: ^command_event}}

      assert_received {^event_name_cache, ^cache_event_ref, %{count: 1},
                       %{event_type: :local_hit}}

      assert_received {^event_name_cache, ^cache_event_ref, %{count: 2},
                       %{event_type: :remote_hit}}

      assert_received {^event_name_cache, ^cache_event_ref, %{count: 1}, %{event_type: :miss}}
    end
  end

  describe "get_command_event_by_id/1" do
    test "returns a command event" do
      # Given
      user = AccountsFixtures.user_fixture()

      command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "generate",
          user_id: user.id
        )
        |> Repo.preload(user: :account)

      # When
      got = CommandEvents.get_command_event_by_id(command_event.id)

      # Then
      assert got == command_event
    end
  end

  describe "has_result_bundle?/1" do
    test "returns true if the result bundle exists" do
      # Given
      project =
        ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      object_key =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      Storage
      |> stub(:object_exists?, fn ^object_key -> true end)

      # When
      got = CommandEvents.has_result_bundle?(command_event)

      # Then
      assert got == true
    end

    test "returns false if the result bundle does not exist" do
      # Given
      project =
        ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      object_key =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      Storage
      |> stub(:object_exists?, fn ^object_key -> false end)

      # When
      got = CommandEvents.has_result_bundle?(command_event)

      # Then
      assert got == false
    end
  end

  describe "get_result_bundle_url/1" do
    test "returns the result bundle URL" do
      # Given
      project =
        ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      object_key =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      Storage
      |> stub(:generate_download_url, fn ^object_key -> "https://tuist.io" end)

      # When
      got = CommandEvents.generate_result_bundle_url(command_event)

      # Then
      assert got == "https://tuist.io"
    end
  end

  describe "list_command_events/1" do
    test "returns command events" do
      # Given
      project = ProjectsFixtures.project_fixture()
      project_two = ProjectsFixtures.project_fixture()

      command_event_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "one",
          duration: 1000,
          created_at: ~N[2024-03-04 01:00:00]
        )
        |> Repo.preload(user: :account)

      CommandEventsFixtures.command_event_fixture(
        project_id: project_two.id,
        name: "xxx",
        duration: 1000,
        created_at: ~N[2024-03-05 02:00:00]
      )

      command_event_two =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "two",
          duration: 500,
          created_at: ~N[2024-03-05 03:00:00]
        )
        |> Repo.preload(user: :account)

      command_event_three =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "three",
          duration: 500,
          created_at: ~N[2024-03-05 04:00:00]
        )
        |> Repo.preload(user: :account)

      command_event_four =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "four",
          duration: 500,
          created_at: ~N[2024-03-05 05:00:00]
        )
        |> Repo.preload(user: :account)

      command_event_five =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "five",
          duration: 500,
          created_at: ~N[2024-03-05 06:00:00]
        )
        |> Repo.preload(user: :account)

      # When
      {got_command_events_first_page, got_meta_first_page} =
        CommandEvents.list_command_events(%{
          first: 2,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:created_at],
          order_directions: [:desc]
        })

      {got_command_events_second_page, got_meta_second_page} =
        CommandEvents.list_command_events(Flop.to_next_cursor(got_meta_first_page))

      {got_command_events_third_page, _meta} =
        CommandEvents.list_command_events(Flop.to_next_cursor(got_meta_second_page))

      # Then
      assert got_command_events_first_page == [command_event_five, command_event_four]
      assert got_command_events_second_page == [command_event_three, command_event_two]
      assert got_command_events_third_page == [command_event_one]
    end

    test "returns command events with preloaded previews" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00]
        )

      # When
      {got_command_events_page, _got_meta_page} =
        CommandEvents.list_command_events(
          %{
            first: 20,
            filters: [%{field: :project_id, op: :==, value: project.id}],
            order_by: [:created_at],
            order_directions: [:desc]
          },
          preload: [:preview]
        )

      # Then
      assert got_command_events_page |> Enum.map(& &1.id) == [
               command_event_two.id,
               command_event_one.id
             ]

      assert got_command_events_page |> Enum.map(& &1.preview) == [
               preview_two,
               preview_one
             ]
    end

    test "returns command events with filtered preview_supported_platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00],
          supported_platforms: [:ios, :watchos]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          supported_platforms: [:macos, :watchos]
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00]
        )

      # When
      {got_command_events_page, _got_meta_page} =
        CommandEvents.list_command_events(
          %{
            first: 20,
            filters: [%{field: :project_id, op: :==, value: project.id}],
            order_by: [:created_at],
            order_directions: [:desc]
          },
          preload: [:preview],
          preview_supported_platforms: [:ios, :visionos]
        )

      # Then
      assert got_command_events_page |> Enum.map(& &1.id) == [
               command_event_one.id
             ]

      assert got_command_events_page |> Enum.map(& &1.preview) == [
               preview_one
             ]
    end

    test "returns command events with preloaded previews and distinct bundle identifiers" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one"
        )

      command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00]
        )

      preview_three =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-two"
        )

      command_event_three =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_three.id,
          created_at: ~N[2021-01-01 02:00:00]
        )

      # When
      {got_command_events_page, _got_meta_page} =
        CommandEvents.list_command_events(
          %{
            first: 20,
            filters: [%{field: :project_id, op: :==, value: project.id}],
            order_by: [:created_at],
            order_directions: [:desc]
          },
          preload: [:preview],
          distinct: [preview: [:bundle_identifier]]
        )

      # Then
      assert got_command_events_page |> Enum.map(& &1.id) == [
               command_event_two.id,
               command_event_three.id
             ]

      assert got_command_events_page |> Enum.map(& &1.preview.bundle_identifier) == [
               "com.example.app-one",
               "com.example.app-two"
             ]
    end
  end

  describe "get_latest_share_command_event/1" do
    test "returns latest share command event" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00],
          git_branch: "main"
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00],
          git_branch: "main"
        )

      _command_event_three =
        CommandEventsFixtures.command_event_fixture(
          name: "generate",
          project_id: project.id,
          created_at: ~N[2021-01-01 02:00:00],
          git_branch: "main"
        )

      # When
      got = CommandEvents.get_latest_share_command_event(project)

      # Then
      assert got.id == command_event_two.id
    end

    test "returns nil when no latest share command event exists" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00],
          git_branch: "other"
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "generate",
          project_id: project.id,
          created_at: ~N[2021-01-01 02:00:00],
          git_branch: "main"
        )

      # When
      got = CommandEvents.get_latest_share_command_event(project)

      # Then
      assert got == nil
    end
  end

  describe "get_total_command_period_average_duration/5" do
    test "returns command average duration" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-03-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 500,
        created_at: ~N[2024-03-05 00:00:00]
      )

      # When
      got =
        CommandEvents.get_total_command_period_average_duration(
          "generate",
          project.id,
          start_date: Date.add(Time.utc_now(), -60),
          end_date: Date.add(Time.utc_now(), -30)
        )

      # Then
      assert got == 1000.0
    end

    test "returns command average duration for CI only" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        is_ci: true,
        created_at: ~N[2024-03-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 500,
        is_ci: false,
        created_at: ~N[2024-03-05 00:00:00]
      )

      # When
      got =
        CommandEvents.get_total_command_period_average_duration(
          "generate",
          project.id,
          start_date: Date.add(Time.utc_now(), -60),
          end_date: Date.add(Time.utc_now(), -30),
          is_ci: true
        )

      # Then
      assert got == 1500.0
    end
  end

  describe "get_command_duration_analytics/4" do
    test "returns duration analytics for the last three days" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-29 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-27 10:00:00]
      )

      # When
      got =
        CommandEvents.get_command_duration_analytics("generate",
          project_id: project.id,
          start_date: Date.add(Time.utc_now(), -2)
        )

      # Then
      assert got.values == [0, 1500.0, 1500.0]
      assert got.trend == -25.0
      assert got.total_average_duration == 1500
    end

    test "returns duration analytics for user runs only" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: false
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-29 10:00:00],
        is_ci: false
      )

      # When
      got =
        CommandEvents.get_command_duration_analytics("generate",
          project_id: project.id,
          start_date: Date.add(Time.utc_now(), -2),
          is_ci: false
        )

      # Then
      assert got.values == [0, 1500.0, 2000.0]
      assert got.trend == 0.0
      assert got.total_average_duration == 1750.0
    end

    test "returns runs analytics for the last 3 days" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-29 01:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-27 01:00:00]
      )

      # When
      got =
        CommandEvents.get_command_runs_analytics("generate",
          project_id: project.id,
          start_date: Date.add(Time.utc_now(), -2)
        )

      # Then
      assert got.values == [0, 1, 2]
      assert got.dates == ["Apr 28", "Apr 29", "Apr 30"]
      assert got.trend == 200
      assert got.runs_count == 3
    end

    test "returns runs analytics for the last year" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-02-29 01:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2023-03-27 01:00:00]
      )

      # When
      got =
        CommandEvents.get_command_runs_analytics("generate",
          project_id: project.id,
          start_date: Date.add(Time.utc_now(), -365)
        )

      # Then
      assert got.values == [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2]

      assert got.dates == [
               "May 2023",
               "Jun 2023",
               "Jul 2023",
               "Aug 2023",
               "Sep 2023",
               "Oct 2023",
               "Nov 2023",
               "Dec 2023",
               "Jan 2024",
               "Feb 2024",
               "Mar 2024",
               "Apr 2024"
             ]

      assert got.trend == 200
      assert got.runs_count == 3
    end
  end

  describe "get_cache_hit_rate_analytics/4" do
    test "returns cache hit rates for the last three days" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["E", "F"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: [],
        remote_cache_target_hits: ["B"],
        created_at: ~N[2024-04-27 03:00:00]
      )

      # When
      got =
        CommandEvents.get_cache_hit_rate_analytics(
          project_id: project.id,
          start_date: Date.add(Time.utc_now(), -2),
          end_date: DateTime.to_date(Time.utc_now())
        )

      # Then
      assert got.values == [0, 0, 0.5]
      assert got.cache_hit_rate == 0.5
    end

    test "returns cache hit rates for the last three days for ci only" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B", "C"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: false
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: [],
        remote_cache_target_hits: ["B"],
        created_at: ~N[2024-04-29 03:00:00],
        is_ci: true
      )

      # When
      got =
        CommandEvents.get_cache_hit_rate_analytics(
          project_id: project.id,
          start_date: Date.add(Time.utc_now(), -2),
          end_date: DateTime.to_date(Time.utc_now()),
          is_ci: true
        )

      # Then
      assert got.values == [0, 0.5, 0.5]
      assert got.cache_hit_rate == 0.5
    end
  end

  describe "get_cache_event/1" do
    test "returns cache download event" do
      # Given
      project = ProjectsFixtures.project_fixture()

      item = %{
        project_id: project.id,
        name: "a",
        event_type: :download,
        size: 1000,
        hash: "hash-1"
      }

      item_upload = %{
        project_id: project.id,
        name: "a",
        event_type: :upload,
        size: 1000,
        hash: "hash-1"
      }

      item_two = %{
        project_id: project.id,
        name: "a",
        event_type: :download,
        size: 1000,
        hash: "hash-2"
      }

      cache_event = CommandEvents.create_cache_event(item)
      CommandEvents.create_cache_event(item_two)
      CommandEvents.create_cache_event(item_upload)

      # When
      got = CommandEvents.get_cache_event(%{hash: "hash-1", event_type: :download})

      # Then
      assert got == cache_event
    end
  end

  test "returns a trend when current_value is smaller" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 20.0, current_value: 10.0)

    # Then
    assert got == -50.0
  end

  test "returns a trend when current_value is bigger" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 10.0, current_value: 20.0)

    # Then
    assert got == 100.0
  end

  test "returns 0 for a trend if previous value is 0" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 0, current_value: 20.0)

    # Then
    assert got == 0
  end

  test "returns 0 for a trend if both values are 0" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 0.0, current_value: 0)

    # Then
    assert got == 0
  end

  describe "update_cache_event_counts/0" do
    test "updates cache event counts" do
      # Given
      Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      user_one = AccountsFixtures.user_fixture()
      account_one = Accounts.get_account_from_user(user_one)
      project_one = ProjectsFixtures.project_fixture(account_id: account_one.id)

      CommandEvents.create_cache_event(%{
        project_id: project_one.id,
        name: "a",
        event_type: :upload,
        size: 1000,
        hash: "hash-1"
      })

      CommandEvents.create_cache_event(%{
        project_id: project_one.id,
        name: "a",
        event_type: :download,
        size: 1000,
        hash: "hash-1"
      })

      CommandEvents.create_cache_event(%{
        project_id: project_one.id,
        name: "b",
        event_type: :download,
        size: 2000,
        created_at: ~N[2024-04-02 03:00:00],
        hash: "hash-2"
      })

      project_two = ProjectsFixtures.project_fixture(account_id: account_one.id)

      CommandEvents.create_cache_event(%{
        project_id: project_two.id,
        name: "c",
        event_type: :upload,
        size: 3000,
        created_at: ~N[2024-04-01 03:00:00],
        hash: "hash-3"
      })

      CommandEvents.create_cache_event(%{
        project_id: project_two.id,
        name: "c",
        event_type: :download,
        size: 3000,
        created_at: ~N[2024-04-01 03:00:00],
        hash: "hash-3"
      })

      CommandEvents.create_cache_event(
        %{
          project_id: project_two.id,
          name: "c",
          event_type: :download,
          size: 10_000,
          hash: "hash-4"
        },
        created_at: ~N[2024-03-29 03:00:00]
      )

      user_two = AccountsFixtures.user_fixture()
      account_two = Accounts.get_account_from_user(user_two)
      project_three = ProjectsFixtures.project_fixture(account_id: account_two.id)

      CommandEvents.create_cache_event(%{
        project_id: project_three.id,
        name: "d",
        event_type: :download,
        size: 4000,
        hash: "hash-5"
      })

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      CommandEvents.update_cache_event_counts()

      # Then
      assert Accounts.get_account_by_id(account_one.id).cache_download_event_count == 3
      assert Accounts.get_account_by_id(account_one.id).cache_upload_event_count == 2
      assert Accounts.get_account_by_id(account_two.id).cache_download_event_count == 1
      assert Accounts.get_account_by_id(account_two.id).cache_upload_event_count == 0
    end
  end

  describe "get_result_bundle_key/1" do
    test "returns the result bundle object key" do
      # Given
      project =
        ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # When
      got = CommandEvents.get_result_bundle_key(command_event)

      # Then
      assert got ==
               "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"
    end
  end

  describe "get_result_bundle_invocation_record_key/1" do
    test "returns the result bundle invocation record object key" do
      # Given
      project =
        ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # When
      got = CommandEvents.get_result_bundle_invocation_record_key(command_event)

      # Then
      assert got ==
               "#{project.account.name}/#{project.name}/runs/#{command_event.id}/invocation_record.json"
    end
  end

  describe "get_result_bundle_object_key/1" do
    test "returns the result bundle object key" do
      # Given
      project =
        ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # When
      got = CommandEvents.get_result_bundle_object_key(command_event, "some-id")

      # Then
      assert got ==
               "#{project.account.name}/#{project.name}/runs/#{command_event.id}/some-id.json"
    end
  end

  describe "get_test_summary/1" do
    test "returns nil if the invocation record does not exist" do
      # Given
      command_event =
        CommandEventsFixtures.command_event_fixture()
        |> Repo.preload(project: :account)

      base_path =
        "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      Storage
      |> stub(:object_exists?, fn ^invocation_record_object_key ->
        false
      end)

      # When
      got = CommandEvents.get_test_summary(command_event)

      # Then
      assert got == nil
    end

    test "gets test summary" do
      # Given
      command_event =
        CommandEventsFixtures.command_event_fixture()
        |> Repo.preload(project: :account)

      base_path =
        "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      Storage
      |> stub(:object_exists?, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      Storage
      |> stub(:get_object_as_string, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      # When
      got = CommandEvents.get_test_summary(command_event)

      # Then
      assert got == %TestSummary{
               failed_tests_count: 1,
               successful_tests_count: 4,
               total_tests_count: 5,
               project_tests: %{
                 "App/MainApp.xcodeproj" => %{
                   "AppTests" => %TargetTestSummary{
                     tests: [
                       %ActionTestMetadata{
                         identifier_url:
                           "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello",
                         test_status: :success,
                         name: "testHello()"
                       }
                     ],
                     status: :success
                   }
                 },
                 "Framework1/Framework1.xcodeproj" => %{
                   "Framework1Tests" => %TargetTestSummary{
                     tests: [
                       %ActionTestMetadata{
                         identifier_url:
                           "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHello",
                         test_status: :success,
                         name: "testHello()"
                       },
                       %ActionTestMetadata{
                         identifier_url:
                           "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHelloFromFramework2",
                         test_status: :success,
                         name: "testHelloFromFramework2()"
                       }
                     ],
                     status: :success
                   }
                 },
                 "Framework2/Framework2.xcodeproj" => %{
                   "Framework2Tests" => %TargetTestSummary{
                     tests: [
                       %ActionTestMetadata{
                         identifier_url:
                           "test://com.apple.xcode/Framework2/Framework2Tests/Framework2Tests/testHello",
                         test_status: :failure,
                         name: "testHello()"
                       },
                       %ActionTestMetadata{
                         identifier_url:
                           "test://com.apple.xcode/Framework2/Framework2Tests/MyPublicClassTests/testHello",
                         test_status: :success,
                         name: "testHello()"
                       }
                     ],
                     status: :failure
                   }
                 }
               }
             }
    end

    test "gets test summary when there's no result bundle" do
      # Given
      command_event =
        CommandEventsFixtures.command_event_fixture()
        |> Repo.preload(project: :account)

      base_path =
        "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      Storage
      |> stub(:object_exists?, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            false
        end
      end)

      Storage
      |> stub(:get_object_as_string, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      # When
      got = CommandEvents.get_test_summary(command_event)

      assert got == %TestSummary{
               failed_tests_count: 0,
               successful_tests_count: 0,
               total_tests_count: 0,
               project_tests: %{}
             }
    end
  end

  describe "list_flaky_test_cases/1" do
    test "lists flaky test cases" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      test_case_one =
        CommandEventsFixtures.test_case_fixture(
          project_id: project.id,
          identifier: "test0",
          flaky: true
        )

      _test_case_two =
        CommandEventsFixtures.test_case_fixture(
          project_id: project.id,
          identifier: "test1",
          flaky: false
        )

      test_case_three =
        CommandEventsFixtures.test_case_fixture(
          project_id: project.id,
          identifier: "test2",
          flaky: true
        )

      command_event_one = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      _command_event_two = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      command_event_three = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      CommandEventsFixtures.test_case_run_fixture(
        test_case_id: test_case_one.id,
        identifier: "test0",
        command_event_id: command_event_one.id,
        status: :failure,
        flaky: true,
        inserted_at: ~N[2024-03-04 01:00:00]
      )

      CommandEventsFixtures.test_case_run_fixture(
        test_case_id: test_case_three.id,
        identifier: "test2",
        command_event_id: command_event_three.id,
        status: :failure,
        flaky: true,
        inserted_at: ~N[2024-03-04 03:00:00]
      )

      # When
      {got_flaky_tests_first_page, got_meta} =
        CommandEvents.list_flaky_test_cases(project, %{
          order_by: [:last_flaky_test_case_run_inserted_at],
          order_directions: [:desc],
          first: 1
        })

      {got_flaky_tests_second_page, got_second_page_meta} =
        CommandEvents.list_flaky_test_cases(project, Flop.to_next_cursor(got_meta))

      # Then
      assert Enum.map(got_flaky_tests_first_page, & &1.identifier) == [
               "test2"
             ]

      assert Enum.map(got_flaky_tests_second_page, & &1.identifier) == [
               "test0"
             ]

      assert got_second_page_meta.has_next_page? == false
    end
  end

  describe "list_test_case_runs/1" do
    test "lists test case runs" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      command_event_one = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      _command_event_two = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      command_event_three = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      command_event_four = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      test_case_one = CommandEventsFixtures.test_case_fixture(project_id: project.id)
      test_case_two = CommandEventsFixtures.test_case_fixture(project_id: project.id)

      test_case_run_one =
        CommandEventsFixtures.test_case_run_fixture(
          test_case_id: test_case_one.id,
          command_event_id: command_event_one.id,
          status: :success,
          created_at: ~N[2024-03-04 01:00:00]
        )

      CommandEventsFixtures.test_case_run_fixture(
        test_case_id: test_case_two.id,
        command_event_id: command_event_one.id,
        status: :failure
      )

      test_case_run_two =
        CommandEventsFixtures.test_case_run_fixture(
          test_case_id: test_case_one.id,
          command_event_id: command_event_three.id,
          status: :success,
          created_at: ~N[2024-03-04 02:00:00]
        )

      CommandEventsFixtures.test_case_run_fixture(
        test_case_id: test_case_one.id,
        command_event_id: command_event_four.id,
        status: :success,
        created_at: ~N[2024-03-04 03:00:00]
      )

      # When
      {got_test_case_runs, _meta} =
        CommandEvents.list_test_case_runs(%{
          first: 2,
          order_by: [:inserted_at],
          order_directions: [:desc],
          filters: [%{field: :test_case_id, op: :==, value: test_case_one.id}]
        })

      # Then
      assert got_test_case_runs |> Enum.map(& &1.id) |> Enum.sort() ==
               [
                 test_case_run_one,
                 test_case_run_two
               ]
               |> Enum.map(& &1.id)
               |> Enum.sort()
    end
  end

  describe "get_test_case_by_identifier/1" do
    test "gets test case" do
      # Given
      test_case = CommandEventsFixtures.test_case_fixture(identifier: "test-case-identifier")

      # When
      got = CommandEvents.get_test_case_by_identifier("test-case-identifier")

      # Then
      assert got == test_case
    end
  end

  describe "create_test_cases/1" do
    test "creates missing test cases" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      CommandEventsFixtures.test_case_fixture(
        identifier: "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHello"
      )

      # When
      CommandEvents.create_test_cases(%{
        test_summary: CommandEventsFixtures.test_summary_fixture(),
        command_event: command_event
      })

      # Then
      assert Repo.all(TestCase) |> Enum.map(& &1.identifier) |> Enum.sort() == [
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHello",
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHelloFromFramework2",
               "test://com.apple.xcode/Framework2/Framework2Tests/Framework2Tests/testHello",
               "test://com.apple.xcode/Framework2/Framework2Tests/MyPublicClassTests/testHello",
               "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello"
             ]
    end
  end

  describe "create_test_case_runs/1" do
    @tag :skip
    test "creates test case runs" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      CommandEvents.create_test_cases(%{
        test_summary: CommandEventsFixtures.test_summary_fixture(),
        command_event: command_event
      })

      test_case =
        CommandEvents.get_test_case_by_identifier(
          "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello"
        )

      test_case_run =
        CommandEventsFixtures.test_case_run_fixture(
          test_case_id: test_case.id,
          status: :failure,
          module_hash: "app-module_hash",
          flaky: false
        )

      # When
      CommandEvents.create_test_case_runs(%{
        test_summary: CommandEventsFixtures.test_summary_fixture(),
        command_event: command_event,
        modules: %{
          "App/MainApp.xcodeproj" => %{"AppTests" => "app-module_hash"},
          "Framework1/Framework1.xcodeproj" => %{
            "Framework1Tests" => "framework1-module_hash"
          },
          "Framework2/Framework2.xcodeproj" => %{
            "Framework2Tests" => "framework2-module_hash"
          }
        }
      })

      # The
      test_case_runs =
        from(t in TestCaseRun, where: t.command_event_id == ^command_event.id)
        |> Repo.all()
        |> Enum.sort_by(& &1.module_hash)

      assert test_case_runs |> Enum.map(& &1.module_hash) == [
               "app-module_hash",
               "framework1-module_hash",
               "framework1-module_hash",
               "framework2-module_hash",
               "framework2-module_hash"
             ]

      assert test_case_runs |> Enum.map(& &1.flaky) == [
               true,
               false,
               false,
               false,
               false
             ]

      assert Repo.get(TestCase, test_case.id).flaky == true

      assert Repo.get(TestCaseRun, test_case_run.id).flaky == true
    end

    @tag :skip
    test "creates test case runs when module hashes are missing" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      CommandEvents.create_test_cases(%{
        test_summary: CommandEventsFixtures.test_summary_fixture(),
        command_event: command_event
      })

      test_case =
        CommandEvents.get_test_case_by_identifier(
          "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello"
        )

      CommandEventsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        status: :failure,
        flaky: false
      )

      # When
      CommandEvents.create_test_case_runs(%{
        test_summary: CommandEventsFixtures.test_summary_fixture(),
        command_event: command_event,
        modules: %{}
      })

      # Then
      test_case_runs =
        from(t in TestCaseRun, where: t.command_event_id == ^command_event.id)
        |> Repo.all()

      assert length(test_case_runs) == 5
    end
  end

  describe "get_command_events_by_name_git_ref_and_remote/1" do
    test "gets command events by name, git ref and remote" do
      # Given
      project = ProjectsFixtures.project_fixture()

      command_event_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          git_commit_sha: "commit-sha-one",
          git_ref: "refs/pull/2/merge"
        )

      command_event_two =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          git_commit_sha: "commit-sha-two",
          git_ref: "refs/pull/2/merge"
        )

      _command_event_three =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          git_commit_sha: "commit-sha-three",
          git_ref: "main"
        )

      # When
      got =
        CommandEvents.get_command_events_by_name_git_ref_and_project(%{
          name: "test",
          git_ref: "refs/pull/2/merge",
          project: project
        })

      # Then
      assert got == [command_event_one, command_event_two]
    end

    test "gets command events by name, git ref and project when there are none" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "test",
          git_commit_sha: "commit-sha-three",
          git_ref: "main",
          project_id: project.id
        )

      # When
      got =
        CommandEvents.get_command_events_by_name_git_ref_and_project(%{
          name: "test",
          git_ref: "refs/pull/2/merge",
          project: project
        })

      # Then
      assert got == []
    end
  end
end
