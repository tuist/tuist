defmodule TuistWeb.BuildRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)
    %{conn: conn, user: user}
  end

  test "shows details of a build run", %{
    conn: conn,
    organization: organization,
    project: project,
    user: user
  } do
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App"
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    assert has_element?(lv, "h1", "App")
  end
end
