defmodule TuistWeb.ProjectDashboardLiveTest do
  use TuistWeb.ConnCase, async: true
  use Tuist.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures

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

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project, organization: organization}
  end

  test "sets the right title", %{conn: conn, organization: organization, project: project} do
    # When
    {:ok, _lv, html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}")

    assert html =~ "Dashboard · tuist-org/tuist · Tuist"
  end
end
