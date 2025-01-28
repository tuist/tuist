defmodule TuistWeb.ProjectRunDetailLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  setup :set_mimic_from_context

  import Phoenix.LiveViewTest
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        creator: user,
        preload: [:account]
      )

    selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    CommandEvents
    |> stub(:get_test_summary, fn _ ->
      %CommandEvents.TestSummary{
        project_tests: %{
          "A/A.xcodeproj" => %{
            "A" => %CommandEvents.TargetTestSummary{tests: [], status: :success}
          },
          "B/B.xcodeproj" => %{
            "B" => %CommandEvents.TargetTestSummary{tests: [], status: :failure}
          }
        },
        failed_tests_count: 1,
        successful_tests_count: 3,
        total_tests_count: 4
      }
    end)

    CommandEvents
    |> stub(:has_result_bundle?, fn _ -> true end)

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project, organization: organization}
  end

  test "errors with not found if the command event does not exist", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given/When/Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/runs/1133332525")
    end
  end

  test "errors with not found if the command event exists but does not belong to the project", %{
    conn: conn,
    organization: organization
  } do
    # Given
    project = ProjectsFixtures.project_fixture()
    different_project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        status: :failure
      )

    # When/Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> live(
        ~p"/#{organization.account.name}/#{different_project.name}/runs/#{command_event.id}"
      )
    end
  end

  test "sets the right title", %{conn: conn, organization: organization, project: project} do
    # Given
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        status: :failure
      )

    # When
    {:ok, _lv, html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/runs/#{command_event.id}")

    assert html =~ "Run · tuist-org/tuist · Tuist"
  end

  test "renders run detail with a failure status", %{conn: conn, project: project} do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        status: :failure
      )

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert has_element?(lv, ":first-of-type(.run-detail__header)", "failure")
    refute has_element?(lv, ":first-of-type(.run-detail__header)", "success")
  end

  test "renders download button if a command event has a result bundle", %{
    conn: conn,
    project: project
  } do
    command_event =
      CommandEventsFixtures.command_event_fixture(project_id: project.id)

    CommandEvents
    |> stub(:has_result_bundle?, fn _ -> true end)

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert lv |> render_async(500) =~ "Result"
  end

  test "does not render a download button if a command event does not have a result bundle", %{
    conn: conn,
    project: project
  } do
    command_event =
      CommandEventsFixtures.command_event_fixture(project_id: project.id)

    CommandEvents
    |> stub(:has_result_bundle?, fn _ -> false end)

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    refute html =~ "Result"
  end

  test "renders run detail with a success status", %{conn: conn, project: project} do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        status: :success
      )

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert has_element?(lv, ":first-of-type(.run-detail__header)", "success")
    refute has_element?(lv, ":first-of-type(.run-detail__header)", "failure")
  end

  test "renders ran by with a user name", %{conn: conn, user: user, project: project} do
    user_account = Accounts.get_account_from_user(user)

    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        user_id: user.id
      )

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert html =~ user_account.name
  end

  test "renders cacheable targets in the alphabetical order with their cache status", %{
    conn: conn,
    project: project
  } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        status: :success
      )

    xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)
    xcode_project_one = XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

    XcodeFixtures.xcode_target_fixture(
      xcode_project_id: xcode_project_one.id,
      name: "A",
      binary_cache_hit: :local,
      binary_cache_hash: "hash-a"
    )

    XcodeFixtures.xcode_target_fixture(
      xcode_project_id: xcode_project_one.id,
      name: "B",
      binary_cache_hit: :remote,
      binary_cache_hash: "hash-b"
    )

    xcode_project_two = XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

    XcodeFixtures.xcode_target_fixture(
      xcode_project_id: xcode_project_two.id,
      name: "C",
      binary_cache_hit: :miss,
      binary_cache_hash: "hash-c"
    )

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert has_element?(lv, "table tbody tr:nth-child(1)", "A")
    assert has_element?(lv, "table tbody tr:nth-child(1)", "Local")

    assert has_element?(lv, "table tbody tr:nth-child(2)", "B")
    assert has_element?(lv, "table tbody tr:nth-child(2)", "Remote")

    assert has_element?(lv, "table tbody tr:nth-child(3)", "C")
    assert has_element?(lv, "table tbody tr:nth-child(3)", "Miss")
  end

  test "renders cacheable targets in the alphabetical order with their cache status using deprecated command_event columns",
       %{
         conn: conn,
         project: project
       } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        status: :success,
        cacheable_targets: ["C", "B", "A"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["B"]
      )

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert has_element?(lv, "table tbody tr:nth-child(1)", "A")
    assert has_element?(lv, "table tbody tr:nth-child(1)", "Local")

    assert has_element?(lv, "table tbody tr:nth-child(2)", "B")
    assert has_element?(lv, "table tbody tr:nth-child(2)", "Remote")

    assert has_element?(lv, "table tbody tr:nth-child(3)", "C")
    assert has_element?(lv, "table tbody tr:nth-child(3)", "Miss")
  end

  test "renders test breakdown card if it has a test summary", %{
    conn: conn,
    project: project
  } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        status: :success
      )

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    # Temporarily disabled due to performance issues
    # assert html =~ "Tests"
    assert has_element?(lv, "table tbody tr:nth-child(1)", "A")
    assert has_element?(lv, "table tbody tr:nth-child(1)", "Success")
    assert has_element?(lv, "table tbody tr:nth-child(2)", "B")
    assert has_element?(lv, "table tbody tr:nth-child(2)", "Failure")
  end

  test "does not render test breakdown card if it does not have a test summary", %{
    conn: conn,
    project: project
  } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        status: :success
      )

    CommandEvents
    |> stub(:get_test_summary, fn _ -> nil end)

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    refute has_element?(lv, "#tests")
  end

  test "renders test targets table if the command name is test", %{
    conn: conn,
    project: project
  } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test"
      )

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert html =~ "Tested targets"
  end

  test "doesn't render test targets table if the command name is not test", %{
    conn: conn,
    project: project
  } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate"
      )

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    refute html =~ "Selective testing hits"
  end

  test "renders test targets in the alphabetical order with their selective test result",
       %{
         conn: conn,
         project: project
       } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        status: :success
      )

    xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)
    xcode_project_one = XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

    XcodeFixtures.xcode_target_fixture(
      xcode_project_id: xcode_project_one.id,
      name: "A",
      selective_testing_hit: :local,
      selective_testing_hash: "hash-a"
    )

    XcodeFixtures.xcode_target_fixture(
      xcode_project_id: xcode_project_one.id,
      name: "B",
      selective_testing_hit: :remote,
      selective_testing_hash: "hash-b"
    )

    xcode_project_two = XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

    XcodeFixtures.xcode_target_fixture(
      xcode_project_id: xcode_project_two.id,
      name: "C",
      selective_testing_hit: :miss,
      selective_testing_hash: "hash-c"
    )

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert has_element?(lv, "table tbody tr:nth-child(1)", "A")
    assert has_element?(lv, "table tbody tr:nth-child(1)", "Local")

    assert has_element?(lv, "table tbody tr:nth-child(2)", "B")
    assert has_element?(lv, "table tbody tr:nth-child(2)", "Remote")

    assert has_element?(lv, "table tbody tr:nth-child(3)", "C")
    assert has_element?(lv, "table tbody tr:nth-child(3)", "Miss")
  end

  test "renders test targets in the alphabetical order with their selective test result using deprecated command_event columns",
       %{
         conn: conn,
         project: project
       } do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        status: :success,
        test_targets: ["C", "B", "A"],
        local_test_target_hits: ["A"],
        remote_test_target_hits: ["B"]
      )

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert has_element?(lv, "table tbody tr:nth-child(1)", "A")
    assert has_element?(lv, "table tbody tr:nth-child(1)", "Local")

    assert has_element?(lv, "table tbody tr:nth-child(2)", "B")
    assert has_element?(lv, "table tbody tr:nth-child(2)", "Remote")

    assert has_element?(lv, "table tbody tr:nth-child(3)", "C")
    assert has_element?(lv, "table tbody tr:nth-child(3)", "Miss")
  end
end
