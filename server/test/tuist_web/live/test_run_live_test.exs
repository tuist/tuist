defmodule TuistWeb.TestRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)
    stub(CommandEvents, :get_command_event_by_test_run_id, fn _ -> {:error, :not_found} end)
    %{conn: conn, user: user}
  end

  test "shows details of a test run", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    assert has_element?(lv, "h1", "Test Run")
  end

  test "shows test cases table", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    assert has_element?(lv, "[data-part='test-cases-card']")
    assert has_element?(lv, "#test-cases-table")
  end
end
