defmodule TuistWeb.XcodeCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "xcode cache page" do
    test "displays empty state when no builds exist", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/xcode-cache")

      assert has_element?(lv, ".tuist-empty-state")
    end

    test "displays analytics widgets when builds exist", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          cacheable_tasks_count: 10,
          cacheable_task_local_hits_count: 5,
          cacheable_task_remote_hits_count: 3
        )

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/xcode-cache")

      assert has_element?(lv, "#widget-cache-uploads")
      assert has_element?(lv, "#widget-cache-downloads")
      assert has_element?(lv, "#widget-cache-hit-rate")
    end
  end
end
