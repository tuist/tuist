defmodule TuistCloudWeb.RunDetailLiveTest do
  use TuistCloudWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias TuistCloud.CommandEventsFixtures
  alias TuistCloud.Accounts
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
    account = Accounts.get_account_from_organization(organization)
    selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:current_owner, "tuist-org")
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

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert html =~ "failure"
    refute html =~ "success"
  end

  test "renders run detail with a success status", %{conn: conn, project: project} do
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        status: :success
      )

    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/tuist/runs/#{command_event.id}")

    assert html =~ "success"
    refute html =~ "failure"
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
end
