defmodule TuistCloudWeb.TestCaseDetailLiveTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

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
      |> assign(:selected_owner, "tuist-org")
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project}
  end

  test "renders rows with their status", %{conn: conn} do
    test_case_identifier = "test_case_identifier"

    test_case = CommandEventsFixtures.test_case_fixture(identifier: test_case_identifier)
    CommandEventsFixtures.test_case_run_fixture(test_case_id: test_case.id, flaky: true)
    CommandEventsFixtures.test_case_run_fixture(test_case_id: test_case.id)

    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/tuist/tests/cases/#{Base.encode64(test_case_identifier)}")

    assert has_element?(lv, "table tbody tr:nth-child(1) *", "flaky")
    assert has_element?(lv, "table tbody tr:nth-child(2) *", "success")
    refute has_element?(lv, "table tbody tr:nth-child(2) *", "flaky")
  end

  test "raises not found error when decoding the base64 identifier fails", %{conn: conn} do
    # When / Then
    assert_raise TuistCloudWeb.Errors.NotFoundError, fn ->
      conn
      |> live(~p"/tuist-org/tuist/tests/cases/invalid-identifier")
    end
  end
end
