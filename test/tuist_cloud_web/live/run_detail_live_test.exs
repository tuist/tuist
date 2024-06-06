defmodule TuistCloudWeb.RunDetailLiveTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  alias TuistCloud.CommandEventsFixtures
  alias TuistCloud.Accounts
  alias TuistCloud.CommandEvents
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
    account = Accounts.get_account_from_organization(organization)
    selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    CommandEvents
    |> stub(:get_test_summary, fn _ ->
      %CommandEvents.TestSummary{
        target_tests: %{
          "A" => %CommandEvents.TargetTestSummary{tests: [], status: :success},
          "B" => %CommandEvents.TargetTestSummary{tests: [], status: :failure}
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
      |> assign(:selected_owner, "tuist-org")
      |> assign(:selected_account, account)
      |> log_in_user(AccountsFixtures.user_fixture())

    %{conn: conn, user: user, project: selected_project}
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

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert html =~ "Result"
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

    {:ok, lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert html =~ "Tests"
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

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    refute html =~ "Tests"
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

  test "renders test targets in the alphabetical order with their test result", %{
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
