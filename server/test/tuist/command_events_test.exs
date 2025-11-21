defmodule Tuist.CommandEventsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.ResultBundle.ActionTestMetadata
  alias Tuist.CommandEvents.TargetTestSummary
  alias Tuist.CommandEvents.TestCase
  alias Tuist.CommandEvents.TestCaseRun
  alias Tuist.CommandEvents.TestSummary
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

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

    test "computes remote_cache_hits_count and remote_test_hits_count on insertion" do
      # When
      command_event =
        CommandEventsFixtures.command_event_fixture(
          remote_cache_target_hits: ["A"],
          remote_test_target_hits: ["ATests"]
        )

      {:ok, reloaded_event} = CommandEvents.get_command_event_by_id(command_event.id)

      # Then
      assert reloaded_event.remote_cache_hits_count == 1
      assert reloaded_event.remote_test_hits_count == 1
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
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture()

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
          project_id: project.id,
          cacheable_targets: ["A", "B", "C", "D"],
          local_cache_target_hits: ["A"],
          remote_cache_target_hits: ["B", "C"],
          remote_cache_hits_count: 2,
          test_targets: [],
          local_test_target_hits: [],
          remote_test_target_hits: [],
          remote_test_hits_count: 0,
          is_ci: false,
          user_id: user.id,
          client_id: "client-id",
          status: :success,
          preview_id: nil,
          git_ref: nil,
          git_commit_sha: nil,
          git_branch: nil,
          error_message: nil,
          ran_at: ~U[2024-03-04 01:00:00Z],
          build_run_id: nil,
          created_at: ~U[2024-03-04 01:00:00Z]
        })

      # Then
      event_name_run_command = Tuist.Telemetry.event_name_run_command()
      event_name_cache = Tuist.Telemetry.event_name_cache()

      assert_received {^event_name_run_command, ^run_create_ref, %{duration: 100}, %{command_event: ^command_event}}

      assert_received {^event_name_cache, ^cache_event_ref, %{count: 1}, %{event_type: :local_hit}}

      assert_received {^event_name_cache, ^cache_event_ref, %{count: 2}, %{event_type: :remote_hit}}

      assert_received {^event_name_cache, ^cache_event_ref, %{count: 1}, %{event_type: :miss}}
    end
  end

  describe "get_command_event_by_id/1" do
    test "returns a command event by uuid string" do
      # Given
      user = AccountsFixtures.user_fixture()

      command_event =
        CommandEventsFixtures.command_event_fixture(name: "generate", user_id: user.id)

      # When
      got = CommandEvents.get_command_event_by_id(command_event.id)

      # Then
      assert {:ok, event} = got
      assert event.id == command_event.id
      assert event.name == command_event.name
      assert event.user_id == command_event.user_id
    end

    test "returns {:error, :not_found} for valid UUID that doesn't exist in database" do
      # Given - a valid UUID that doesn't exist in the database
      non_existent_uuid = Ecto.UUID.generate()

      # When
      got = CommandEvents.get_command_event_by_id(non_existent_uuid)

      # Then
      assert got == {:error, :not_found}
    end

    test "returns {:error, :not_found} for malformed UUID string" do
      # Given - various malformed UUID strings
      malformed_uuids = [
        "not-a-uuid",
        # Too short
        "12345678-1234-1234-1234-12345678901",
        # Too long
        "12345678-1234-1234-1234-1234567890123",
        # Invalid character
        "12345678-1234-1234-1234-123456789g12",
        # Invalid character at start
        "g2345678-1234-1234-1234-123456789012",
        ""
      ]

      # When/Then
      for malformed_uuid <- malformed_uuids do
        got = CommandEvents.get_command_event_by_id(malformed_uuid)

        assert got == {:error, :not_found},
               "Expected {:error, :not_found} for #{inspect(malformed_uuid)}"
      end
    end
  end

  describe "has_result_bundle?/1" do
    test "returns true if the result bundle exists" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      object_key =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      stub(Storage, :object_exists?, fn ^object_key, _actor -> true end)

      # When
      got = CommandEvents.has_result_bundle?(command_event)

      # Then
      assert got == true
    end

    test "returns false if the result bundle does not exist" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      object_key =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      stub(Storage, :object_exists?, fn ^object_key, _actor -> false end)

      # When
      got = CommandEvents.has_result_bundle?(command_event)

      # Then
      assert got == false
    end
  end

  describe "get_result_bundle_url/1" do
    test "returns the result bundle URL" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      object_key =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      stub(Storage, :generate_download_url, fn ^object_key, _actor -> "https://tuist.io" end)

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

      command_event_three =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "three",
          duration: 500,
          created_at: ~N[2024-03-05 04:00:00]
        )

      command_event_four =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "four",
          duration: 500,
          created_at: ~N[2024-03-05 05:00:00]
        )

      command_event_five =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "five",
          duration: 500,
          created_at: ~N[2024-03-05 06:00:00]
        )

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
      assert got_command_events_first_page == [
               command_event_five.id |> CommandEvents.get_command_event_by_id() |> elem(1),
               command_event_four.id |> CommandEvents.get_command_event_by_id() |> elem(1)
             ]

      assert got_command_events_second_page == [
               command_event_three.id |> CommandEvents.get_command_event_by_id() |> elem(1),
               command_event_two.id |> CommandEvents.get_command_event_by_id() |> elem(1)
             ]

      assert got_command_events_third_page == [
               command_event_one.id |> CommandEvents.get_command_event_by_id() |> elem(1)
             ]
    end
  end

  describe "list_test_runs/1" do
    test "returns test runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      _project_two = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "xcodebuild",
        subcommand: "build",
        duration: 1000,
        created_at: ~N[2024-03-04 01:00:00]
      )

      _command_event_four =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "four",
          duration: 500,
          created_at: ~N[2024-03-05 05:00:00]
        )

      command_event_two =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "xcodebuild",
          subcommand: "test",
          duration: 500,
          created_at: ~N[2024-03-05 03:00:00]
        )

      command_event_three =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "xcodebuild",
          subcommand: "test",
          duration: 500,
          created_at: ~N[2024-03-05 04:00:00]
        )

      command_event_five =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          duration: 500,
          created_at: ~N[2024-03-05 06:00:00]
        )

      # When
      {got_command_events_first_page, got_meta_first_page} =
        CommandEvents.list_test_runs(%{
          first: 2,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:created_at],
          order_directions: [:desc]
        })

      {got_command_events_second_page, _got_meta_second_page} =
        CommandEvents.list_test_runs(Flop.to_next_cursor(got_meta_first_page))

      # Then
      assert got_command_events_first_page == [
               command_event_five.id |> CommandEvents.get_command_event_by_id() |> elem(1),
               command_event_three.id |> CommandEvents.get_command_event_by_id() |> elem(1)
             ]

      assert got_command_events_second_page == [
               command_event_two.id |> CommandEvents.get_command_event_by_id() |> elem(1)
             ]
    end
  end

  describe "get_command_event_by_id/2 with parsing" do
    test "finds command event by legacy_id when passed an integer" do
      # Given
      command_event =
        CommandEventsFixtures.command_event_fixture()

      # When
      result = CommandEvents.get_command_event_by_id(command_event.legacy_id)

      # Then
      assert {:ok, found_event} = result
      assert found_event.id == command_event.id
      assert found_event.legacy_id == command_event.legacy_id
    end

    test "finds command event by integer ID when ID exists" do
      # Given
      command_event =
        CommandEventsFixtures.command_event_fixture()

      # When
      result = CommandEvents.get_command_event_by_id(command_event.id)

      # Then
      assert {:ok, found_event} = result
      assert found_event.id == command_event.id
    end

    test "finds command event by UUID string when ID exists" do
      # Given
      command_event =
        CommandEventsFixtures.command_event_fixture()

      # When
      result = CommandEvents.get_command_event_by_id(command_event.id)

      # Then
      assert {:ok, event} = result
      assert event.id == command_event.id
    end

    test "finds command event by UUID string" do
      # Given
      command_event =
        CommandEventsFixtures.command_event_fixture()

      # When
      result = CommandEvents.get_command_event_by_id(command_event.id)

      # Then
      assert {:ok, event} = result
      assert event.id == command_event.id
    end

    test "returns {:error, :not_found} for non-numeric, non-UUID string" do
      # When
      result = CommandEvents.get_command_event_by_id("not-a-number")

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for string with trailing characters" do
      # When
      result = CommandEvents.get_command_event_by_id("123abc")

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for string with leading characters" do
      # When
      result = CommandEvents.get_command_event_by_id("abc123")

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for nil" do
      # When
      result = CommandEvents.get_command_event_by_id(nil)

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for empty string" do
      # When
      result = CommandEvents.get_command_event_by_id("")

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for string with only whitespace" do
      # When
      result = CommandEvents.get_command_event_by_id("   ")

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for non-existent UUID string" do
      # When
      result = CommandEvents.get_command_event_by_id("00000000-0000-0000-0000-000000000000")

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for non-existent UUID" do
      # When
      result = CommandEvents.get_command_event_by_id(Ecto.UUID.generate())

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for invalid UUID format" do
      # When
      result = CommandEvents.get_command_event_by_id("550e8400-invalid-uuid-format")

      # Then
      assert result == {:error, :not_found}
    end

    test "handles invalid UUID format" do
      # When
      result = CommandEvents.get_command_event_by_id("invalid-uuid")

      # Then
      assert result == {:error, :not_found}
    end

    test "handles malformed UUID strings" do
      # When
      result = CommandEvents.get_command_event_by_id("not-a-uuid-at-all")

      # Then
      assert result == {:error, :not_found}
    end

    test "returns {:error, :not_found} for other data types" do
      # When
      result = CommandEvents.get_command_event_by_id(%{})

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "get_result_bundle_key/1" do
    test "returns the result bundle object key" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

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
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

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
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

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
      command_event = CommandEventsFixtures.command_event_fixture()
      {:ok, project} = CommandEvents.get_project_for_command_event(command_event)
      project = Repo.preload(project, :account)

      base_path =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      stub(Storage, :object_exists?, fn ^invocation_record_object_key, _actor ->
        false
      end)

      # When
      got = CommandEvents.get_test_summary(command_event)

      # Then
      assert got == nil
    end

    test "gets test summary" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()
      {:ok, project} = CommandEvents.get_project_for_command_event(command_event)
      project = Repo.preload(project, :account)

      base_path =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      stub(Storage, :object_exists?, fn object_key, _actor ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      stub(Storage, :get_object_as_string, fn object_key, _actor ->
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
                         identifier_url: "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello",
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
                         identifier_url: "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHello",
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
                         identifier_url: "test://com.apple.xcode/Framework2/Framework2Tests/Framework2Tests/testHello",
                         test_status: :failure,
                         name: "testHello()"
                       },
                       %ActionTestMetadata{
                         identifier_url: "test://com.apple.xcode/Framework2/Framework2Tests/MyPublicClassTests/testHello",
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
      command_event = CommandEventsFixtures.command_event_fixture()
      {:ok, project} = CommandEvents.get_project_for_command_event(command_event)
      project = Repo.preload(project, :account)

      base_path =
        "#{project.account.name}/#{project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      stub(Storage, :object_exists?, fn object_key, _actor ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            false
        end
      end)

      stub(Storage, :get_object_as_string, fn object_key, _actor ->
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
          inserted_at: ~N[2024-03-04 03:00:00]
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
          inserted_at: ~N[2024-03-04 02:00:00]
        )

      CommandEventsFixtures.test_case_run_fixture(
        test_case_id: test_case_one.id,
        command_event_id: command_event_four.id,
        status: :success,
        inserted_at: ~N[2024-03-04 01:00:00]
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
      assert TestCase |> Repo.all() |> Enum.map(& &1.identifier) |> Enum.sort() == [
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHello",
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHelloFromFramework2",
               "test://com.apple.xcode/Framework2/Framework2Tests/Framework2Tests/testHello",
               "test://com.apple.xcode/Framework2/Framework2Tests/MyPublicClassTests/testHello",
               "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello"
             ]
    end
  end

  describe "create_test_case_runs/1" do
    test "creates test case runs" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      test_summary =
        CommandEventsFixtures.test_summary_fixture(
          project_tests: %{
            "App/MainApp.xcodeproj" => %{
              "AppTests" => %TargetTestSummary{
                tests: [
                  %ActionTestMetadata{
                    test_status: :success,
                    name: "testHello()",
                    identifier_url: "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello"
                  }
                ],
                status: :success
              }
            },
            "Framework2/Framework2.xcodeproj" => %{
              "Framework2Tests" => %TargetTestSummary{
                tests: [
                  %ActionTestMetadata{
                    test_status: :failure,
                    name: "testHello()",
                    identifier_url: "test://com.apple.xcode/Framework2/Framework2Tests/Framework2Tests/testHello"
                  },
                  %ActionTestMetadata{
                    test_status: :success,
                    name: "testHello()",
                    identifier_url: "test://com.apple.xcode/Framework2/Framework2Tests/MyPublicClassTests/testHello"
                  }
                ],
                status: :failure
              }
            }
          }
        )

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(
          name: "MainApp",
          path: "App",
          xcode_graph_id: xcode_graph.id
        )

      xcode_target =
        XcodeFixtures.xcode_target_fixture(name: "AppTests", xcode_project_id: xcode_project.id)

      xcode_project_two =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework2",
          path: "Framework2",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_two =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework2Tests",
          xcode_project_id: xcode_project_two.id
        )

      CommandEvents.create_test_cases(%{
        test_summary: test_summary,
        command_event: command_event
      })

      test_case =
        CommandEvents.get_test_case_by_identifier("test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello")

      test_case_run =
        CommandEventsFixtures.test_case_run_fixture(
          test_case_id: test_case.id,
          status: :failure,
          xcode_target_id: xcode_target.id,
          flaky: false
        )

      # When
      CommandEvents.create_test_case_runs(%{
        test_summary: test_summary,
        command_event: command_event
      })

      # The
      test_case_runs =
        Repo.all(
          from(t in TestCaseRun,
            where: t.command_event_id == ^command_event.id,
            order_by: t.xcode_target_id
          )
        )

      assert test_case_runs |> Enum.map(& &1.flaky) |> Enum.sort() == [
               false,
               false,
               true
             ]

      assert Repo.get(TestCase, test_case.id).flaky == true

      assert Repo.get(TestCaseRun, test_case_run.id).flaky == true
    end
  end

  describe "get_user_account_names_for_runs/1" do
    test "returns user account names for runs with users" do
      # Given
      user1 = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()

      run1 = CommandEventsFixtures.command_event_fixture(user_id: user1.id)
      run2 = CommandEventsFixtures.command_event_fixture(user_id: user2.id)
      run3 = CommandEventsFixtures.command_event_fixture(user_id: user1.id)

      # When
      result = CommandEvents.get_user_account_names_for_runs([run1, run2, run3])

      # Then
      assert result == %{
               run1.id => user1.account.name,
               run2.id => user2.account.name,
               run3.id => user1.account.name
             }
    end

    test "returns nil for runs without users" do
      # Given
      user = AccountsFixtures.user_fixture()

      run_with_user = CommandEventsFixtures.command_event_fixture(user_id: user.id)
      run_without_user = CommandEventsFixtures.command_event_fixture(user_id: nil, is_ci: true)

      # When
      result = CommandEvents.get_user_account_names_for_runs([run_with_user, run_without_user])

      # Then
      assert result == %{
               run_with_user.id => user.account.name,
               run_without_user.id => nil
             }
    end

    test "handles empty list of runs" do
      # When
      result = CommandEvents.get_user_account_names_for_runs([])

      # Then
      assert result == %{}
    end

    test "handles runs with non-existent user IDs" do
      # Given
      user = AccountsFixtures.user_fixture()
      non_existent_user_id = 999_999

      run_with_valid_user =
        CommandEventsFixtures.command_event_fixture(user_id: user.id)

      run_with_invalid_user =
        CommandEventsFixtures.command_event_fixture(user_id: non_existent_user_id)

      # When
      result =
        CommandEvents.get_user_account_names_for_runs([
          run_with_valid_user,
          run_with_invalid_user
        ])

      # Then
      assert result == %{
               run_with_valid_user.id => user.account.name,
               run_with_invalid_user.id => nil
             }
    end

    test "efficiently batches database queries" do
      # Given
      user1 = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()

      # Create multiple runs with the same users to test batching
      runs = [
        CommandEventsFixtures.command_event_fixture(user_id: user1.id),
        CommandEventsFixtures.command_event_fixture(user_id: user2.id),
        CommandEventsFixtures.command_event_fixture(user_id: user1.id),
        CommandEventsFixtures.command_event_fixture(user_id: user2.id),
        CommandEventsFixtures.command_event_fixture(user_id: nil, is_ci: true)
      ]

      # When
      result = CommandEvents.get_user_account_names_for_runs(runs)

      # Then
      assert map_size(result) == 5
      assert result[Enum.at(runs, 0).id] == user1.account.name
      assert result[Enum.at(runs, 1).id] == user2.account.name
      assert result[Enum.at(runs, 2).id] == user1.account.name
      assert result[Enum.at(runs, 3).id] == user2.account.name
      assert result[Enum.at(runs, 4).id] == nil
    end
  end

  describe "run_count/7" do
    test "returns count data with date range and filters" do
      # Given
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 1000,
        ran_at: ~U[2024-01-15 12:00:00Z],
        is_ci: false
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 2000,
        ran_at: ~U[2024-01-15 14:00:00Z],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        duration: 1500,
        ran_at: ~U[2024-01-15 16:00:00Z],
        is_ci: false
      )

      # When - test with is_ci filter (this should catch the regression)
      result =
        CommandEvents.run_count(
          project.id,
          ~D[2024-01-10],
          ~D[2024-01-20],
          :day,
          :day,
          "test",
          is_ci: false
        )

      # Then
      # 11 days in range
      assert length(result) == 11
    end

    test "works with status filter" do
      # Given
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 1000,
        ran_at: ~U[2024-01-15 12:00:00Z],
        is_ci: true,
        status: :success
      )

      # When - test with multiple filters (this should catch the regression)
      result =
        CommandEvents.run_count(
          project.id,
          ~D[2024-01-10],
          ~D[2024-01-20],
          :day,
          :day,
          "test",
          is_ci: true,
          status: :success
        )

      # Then
      # 11 days in range
      assert length(result) == 11
    end
  end

  describe "run_average_durations/7" do
    test "returns average duration data with date range and filters" do
      # Given
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 1000,
        ran_at: ~U[2024-01-15 12:00:00Z],
        is_ci: false
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 2000,
        ran_at: ~U[2024-01-15 14:00:00Z],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        duration: 1500,
        ran_at: ~U[2024-01-15 16:00:00Z],
        is_ci: false
      )

      result =
        CommandEvents.run_average_durations(
          project.id,
          ~D[2024-01-10],
          ~D[2024-01-20],
          :day,
          :day,
          "test",
          is_ci: false
        )

      # Then
      # 11 days in range
      assert length(result) == 11
      assert Enum.any?(result, fn %{value: value} -> value > 0 end)
    end

    test "works with status filter" do
      # Given
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 1000,
        ran_at: ~U[2024-01-15 12:00:00Z],
        is_ci: true,
        status: :success
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 2000,
        ran_at: ~U[2024-01-15 14:00:00Z],
        is_ci: true,
        status: :success
      )

      # When - test with multiple filters (this should catch the regression)
      result =
        CommandEvents.run_average_durations(
          project.id,
          ~D[2024-01-10],
          ~D[2024-01-20],
          :day,
          :day,
          "test",
          is_ci: true,
          status: :success
        )

      # Then
      # 11 days in range
      assert length(result) == 11
      assert Enum.any?(result, fn %{value: value} -> value > 0 end)
    end

    test "regression test - should not fail with unknown bind name error" do
      # Given
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        duration: 1000,
        ran_at: ~U[2024-01-15 12:00:00Z],
        is_ci: false
      )

      # When - this specific combination was causing the regression
      # The function should not raise an "unknown bind name :event" error
      result =
        CommandEvents.run_average_durations(
          project.id,
          ~D[2024-01-10],
          ~D[2024-01-20],
          :day,
          :day,
          "test",
          is_ci: false
        )

      # Then - should not raise an exception and return expected data
      assert length(result) == 11
    end
  end

  describe "get_yesterdays_remote_cache_hits_count_for_customer/1" do
    test "counts only yesterday's events for the customer's projects" do
      # Given
      %{account: %{id: account_id}, id: user_id} =
        AccountsFixtures.user_fixture(customer_id: "cust_" <> UUIDv7.generate())

      %{account: %{id: other_account_id}, id: other_user_id} =
        AccountsFixtures.user_fixture(customer_id: "cust_" <> UUIDv7.generate())

      project = ProjectsFixtures.project_fixture(account_id: account_id)
      other_project = ProjectsFixtures.project_fixture(account_id: other_account_id)

      today = ~U[2025-01-02 12:00:00Z]
      stub(DateTime, :utc_now, fn -> today end)

      CommandEventsFixtures.command_event_fixture(
        name: "generate",
        project_id: project.id,
        user_id: user_id,
        remote_cache_target_hits: ["A"],
        ran_at: ~U[2025-01-01 10:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        name: "test",
        project_id: project.id,
        user_id: user_id,
        remote_test_target_hits: ["B"],
        ran_at: ~U[2025-01-01 18:00:00Z]
      )

      # One event for another customer yesterday
      CommandEventsFixtures.command_event_fixture(
        name: "generate",
        project_id: other_project.id,
        user_id: other_user_id,
        remote_cache_target_hits: ["C"],
        ran_at: ~U[2025-01-01 09:00:00Z]
      )

      # Event outside of yesterday window for our project
      CommandEventsFixtures.command_event_fixture(
        name: "generate",
        project_id: project.id,
        user_id: user_id,
        remote_cache_target_hits: ["D"],
        ran_at: ~U[2024-12-31 23:59:59Z]
      )

      # When
      customer_id = Repo.get!(Tuist.Accounts.Account, account_id).customer_id
      count = CommandEvents.get_yesterdays_remote_cache_hits_count_for_customer(customer_id)

      # Then
      assert count == 2
    end
  end

  describe "cache_hit_rate_percentiles/6" do
    test "returns percentile hit rates grouped by date" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Day 1: Multiple runs with different hit rates
      # Run 1: 50% hit rate (1 hit out of 2 cacheable)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-29 10:00:00Z]
      )

      # Run 2: 75% hit rate (3 hits out of 4 cacheable)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        ran_at: ~U[2024-04-29 12:00:00Z]
      )

      # Run 3: 100% hit rate (2 hits out of 2 cacheable)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["B"],
        ran_at: ~U[2024-04-29 14:00:00Z]
      )

      # Day 2: Different hit rates
      # Run 4: 25% hit rate (1 hit out of 4 cacheable)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 10:00:00Z]
      )

      # Run 5: 60% hit rate (3 hits out of 5 cacheable)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D", "E"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        ran_at: ~U[2024-04-30 11:00:00Z]
      )

      # When - p50 (median)
      got =
        CommandEvents.cache_hit_rate_percentiles(
          project.id,
          ~D[2024-04-29],
          ~D[2024-04-30],
          :day,
          "1 day",
          0.5,
          []
        )

      # Then
      assert length(got) == 2

      day1 = Enum.find(got, &(&1.date == "2024-04-29"))
      # p50 of [50%, 75%, 100%] = 75%
      assert day1.percentile_hit_rate == 75.0

      day2 = Enum.find(got, &(&1.date == "2024-04-30"))
      # p50 of [25%, 60%] = 42.5%
      assert day2.percentile_hit_rate == 42.5
    end

    test "returns p90 percentile for high percentile queries" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Create runs with hit rates: 10%, 20%, 30%, 40%, 50%, 60%, 70%, 80%, 90%, 100%
      for i <- 1..10 do
        hit_count = i
        total_count = 10

        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "build",
          cacheable_targets: List.duplicate("T", total_count),
          local_cache_target_hits: List.duplicate("T", hit_count),
          remote_cache_target_hits: [],
          ran_at: ~U[2024-04-30 10:00:00Z]
        )
      end

      # When - p90 (90th percentile)
      # With flipped percentile, p90 means 90% of runs achieved this hit rate or BETTER
      # So we want the 10th percentile in ascending order
      got =
        CommandEvents.cache_hit_rate_percentiles(
          project.id,
          ~D[2024-04-30],
          ~D[2024-04-30],
          :day,
          "1 day",
          0.9,
          []
        )

      # Then
      assert length(got) == 1
      day = List.first(got)
      # p90 should be a lower value since 90% of runs are at or above this
      assert day.percentile_hit_rate <= 20.0
    end

    test "filters by is_ci when specified" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # CI runs with high hit rates
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: [],
        is_ci: true,
        ran_at: ~U[2024-04-30 10:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B", "C"],
        remote_cache_target_hits: ["D"],
        is_ci: true,
        ran_at: ~U[2024-04-30 11:00:00Z]
      )

      # Local runs with low hit rates (should be excluded)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        is_ci: false,
        ran_at: ~U[2024-04-30 12:00:00Z]
      )

      # When - filter for CI only
      got =
        CommandEvents.cache_hit_rate_percentiles(
          project.id,
          ~D[2024-04-30],
          ~D[2024-04-30],
          :day,
          "1 day",
          0.5,
          is_ci: true
        )

      # Then
      assert length(got) == 1
      day = List.first(got)
      # p50 of [100%, 100%] = 100%
      assert day.percentile_hit_rate == 100.0
    end

    test "only includes events with cacheable_targets_count > 0" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Run with cacheable targets
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 10:00:00Z]
      )

      # Run without cacheable targets (should be excluded)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: [],
        local_cache_target_hits: [],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 11:00:00Z]
      )

      # When
      got =
        CommandEvents.cache_hit_rate_percentiles(
          project.id,
          ~D[2024-04-30],
          ~D[2024-04-30],
          :day,
          "1 day",
          0.5,
          []
        )

      # Then
      assert length(got) == 1
      day = List.first(got)
      # Only one event with 50% hit rate
      assert day.percentile_hit_rate == 50.0
    end

    test "groups by hour when using hour bucket" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Hour 1
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 10:15:00Z]
      )

      # Hour 2
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B", "C", "D"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 11:30:00Z]
      )

      # When
      got =
        CommandEvents.cache_hit_rate_percentiles(
          project.id,
          ~D[2024-04-30],
          ~D[2024-04-30],
          :day,
          "1 hour",
          0.5,
          []
        )

      # Then
      assert length(got) == 2

      hour1 = Enum.find(got, &(&1.date == "2024-04-30 10:00:00"))
      assert hour1.percentile_hit_rate == 50.0

      hour2 = Enum.find(got, &(&1.date == "2024-04-30 11:00:00"))
      assert hour2.percentile_hit_rate == 100.0
    end

    test "returns empty list when no events exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        CommandEvents.cache_hit_rate_percentiles(
          project.id,
          ~D[2024-04-30],
          ~D[2024-04-30],
          :day,
          "1 day",
          0.5,
          []
        )

      # Then
      assert got == []
    end
  end

  describe "cache_hit_rate_period_percentile/4" do
    test "returns single percentile value for entire period" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Create runs with different hit rates: 25%, 50%, 75%, 100%
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-29 10:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-29 12:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        ran_at: ~U[2024-04-30 10:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 11:00:00Z]
      )

      # When - p50 (median)
      got =
        CommandEvents.cache_hit_rate_period_percentile(
          project.id,
          ~D[2024-04-29],
          ~D[2024-04-30],
          0.5,
          []
        )

      # Then - p50 of [25%, 50%, 75%, 100%] = 62.5%
      assert got == 62.5
    end

    test "filters by is_ci when specified" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # CI runs with high hit rates
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: [],
        is_ci: true,
        ran_at: ~U[2024-04-30 10:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B", "C"],
        remote_cache_target_hits: ["D"],
        is_ci: true,
        ran_at: ~U[2024-04-30 11:00:00Z]
      )

      # Local runs with low hit rates (should be excluded)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        is_ci: false,
        ran_at: ~U[2024-04-30 12:00:00Z]
      )

      # When - filter for CI only
      got =
        CommandEvents.cache_hit_rate_period_percentile(
          project.id,
          ~D[2024-04-30],
          ~D[2024-04-30],
          0.5,
          is_ci: true
        )

      # Then - p50 of [100%, 100%] = 100%
      assert got == 100.0
    end

    test "only includes events with cacheable_targets_count > 0" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Run with cacheable targets
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 10:00:00Z]
      )

      # Run without cacheable targets (should be excluded)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        cacheable_targets: [],
        local_cache_target_hits: [],
        remote_cache_target_hits: [],
        ran_at: ~U[2024-04-30 11:00:00Z]
      )

      # When
      got =
        CommandEvents.cache_hit_rate_period_percentile(
          project.id,
          ~D[2024-04-30],
          ~D[2024-04-30],
          0.5,
          []
        )

      # Then - Only one event with 50% hit rate
      assert got == 50.0
    end
  end

  describe "get_project_last_interaction_data/1" do
    test "returns last interaction time for specified projects only" do
      project1 = ProjectsFixtures.project_fixture()
      project2 = ProjectsFixtures.project_fixture()
      project3 = ProjectsFixtures.project_fixture()

      now = DateTime.utc_now()
      CommandEventsFixtures.command_event_fixture(project_id: project1.id, ran_at: DateTime.add(now, -5, :day))
      CommandEventsFixtures.command_event_fixture(project_id: project2.id, ran_at: DateTime.add(now, -3, :day))
      CommandEventsFixtures.command_event_fixture(project_id: project3.id, ran_at: DateTime.add(now, -1, :day))

      result = CommandEvents.get_project_last_interaction_data([project1.id, project3.id])

      assert map_size(result) == 2
      assert Map.has_key?(result, project1.id)
      assert Map.has_key?(result, project3.id)
      refute Map.has_key?(result, project2.id)
    end

    test "returns most recent interaction when multiple events exist" do
      project = ProjectsFixtures.project_fixture()

      now = DateTime.utc_now()
      CommandEventsFixtures.command_event_fixture(project_id: project.id, ran_at: DateTime.add(now, -10, :day))
      CommandEventsFixtures.command_event_fixture(project_id: project.id, ran_at: DateTime.add(now, -5, :day))

      most_recent =
        CommandEventsFixtures.command_event_fixture(project_id: project.id, ran_at: DateTime.add(now, -1, :day))

      result = CommandEvents.get_project_last_interaction_data([project.id])

      assert result[project.id] == most_recent.ran_at
    end

    test "returns empty map when no interactions found" do
      project = ProjectsFixtures.project_fixture()

      result = CommandEvents.get_project_last_interaction_data([project.id])

      assert result == %{}
    end
  end
end
