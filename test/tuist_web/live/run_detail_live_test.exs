defmodule TuistWeb.RunDetailLiveTest do
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    FunWithFlags |> Mimic.stub(:enabled?, fn _ -> true end)
    user = AccountsFixtures.user_fixture()
    %{conn: conn, user: user}
  end

  test "shows details of a test run", %{
    conn: conn,
    organization: organization,
    project: project,
    user: user
  } do
    # Given
    test_run =
      CommandEventsFixtures.command_event_fixture(
        project: project,
        name: "test",
        command_arguments: ["test", "App"],
        test_targets: ["AppTests"],
        user_id: user.id
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/runs/#{test_run.id}")

    # Then
    assert has_element?(lv, "span", "Test Optimizations")
    assert has_element?(lv, "span", "tuist test App")
  end

  test "shows details of a cache run", %{
    conn: conn,
    organization: organization,
    project: project,
    user: user
  } do
    # Given
    cache_run =
      CommandEventsFixtures.command_event_fixture(
        project: project,
        name: "cache",
        command_arguments: ["cache"],
        cacheable_targets: ["Framework"],
        user_id: user.id
      )

    xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: cache_run.id)

    xcode_project =
      XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

    _xcode_target =
      XcodeFixtures.xcode_target_fixture(
        name: "AppTests",
        xcode_project_id: xcode_project.id,
        binary_cache_hash: "AppTests-hash"
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(
        ~p"/noora/#{organization.account.name}/#{project.name}/runs/#{cache_run.id}?tab=compilation-optimizations"
      )

    # Then
    assert has_element?(lv, "span", "Compilation Optimizations")
    assert has_element?(lv, "table span", "AppTests")
    assert has_element?(lv, "table span", "AppTests-hash")
  end
end
