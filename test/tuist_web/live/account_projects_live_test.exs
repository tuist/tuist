defmodule TuistWeb.AccountProjectsLiveTest do
  use TuistWeb.ConnCase, async: true
  use Tuist.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preloads: [:account])

    organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        customer_id: "customer_id",
        creator: user,
        preloads: [:account]
      )

    conn = conn |> log_in_user(user)

    %{conn: conn, user: user, organization: organization}
  end

  test "sets the right title", %{conn: conn, organization: organization} do
    # When
    {:ok, _lv, html} =
      conn
      |> live(~p"/#{organization.account.name}/projects")

    assert html =~ "Projects · tuist-org · Tuist"
  end

  test "it shows the get started content when there are no projects", %{
    conn: conn,
    organization: organization
  } do
    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/projects")

    # Then
    assert has_element?(lv, ".account__projects__get-started")
  end

  test "it shows the list of projects if the organization has projects", %{
    conn: conn,
    organization: organization
  } do
    # Given
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/projects")

    # Then
    selector =
      ".account__projects__panel__list > .account__projects__panel__list__item[href=\"#{~p"/#{organization.account.name}/#{project.name}"}\"}]"

    assert has_element?(
             lv,
             selector,
             project.name
           )
  end

  test "raises an error if the user is not authorized to view the projects", %{
    organization: organization
  } do
    # Given
    new_user = AccountsFixtures.user_fixture(preloads: [:account])
    conn = build_conn() |> log_in_user(new_user)

    # When
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> live(~p"/#{organization.account.name}/projects")
    end
  end
end
