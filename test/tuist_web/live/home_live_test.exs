defmodule TuistWeb.HomeLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    account = Accounts.get_account_from_organization(organization)
    selected_project = ProjectsFixtures.project_fixture(account_id: account.id)

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project, account: account}
  end

  test "renders home when a user is anonymous and a project is public" do
    # Given
    project =
      ProjectsFixtures.project_fixture(visibility: :public)
      |> Repo.preload(:account)

    conn =
      build_conn()
      |> assign(:selected_project, project)
      |> assign(:selected_account, project.account)

    # When
    {:ok, _lv, html} = conn |> live(~p"/#{project.account.name}/#{project.name}")

    # Then
    assert html =~ "Sign in"
    assert html =~ "Dashboard"
  end

  test "renders home with a cache hit rate", %{conn: conn, project: project, account: account} do
    Tuist.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: ["A", "B", "C", "D"],
      local_cache_target_hits: ["A"],
      remote_cache_target_hits: ["C", "D"],
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: ["A", "B"],
      local_cache_target_hits: [],
      remote_cache_target_hits: ["B"],
      created_at: ~N[2024-04-29 03:00:00]
    )

    {:ok, _lv, html} =
      conn
      |> live(~p"/#{account.name}/#{project.name}")

    assert html =~ "66.7 %"
  end

  test "renders home with a cache hit rate for CI only", %{
    conn: conn,
    project: project,
    account: account
  } do
    Tuist.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: ["A", "B", "C", "D"],
      local_cache_target_hits: ["A"],
      remote_cache_target_hits: ["C", "D"],
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

    {:ok, _lv, html} =
      conn
      |> live(~p"/#{account.name}/#{project.name}?ran_by[]=ci")

    assert html =~ "50.0 %"
  end
end
