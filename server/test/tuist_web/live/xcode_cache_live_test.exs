defmodule TuistWeb.XcodeCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  describe "xcode cache page" do
    test "displays analytics widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/xcode-cache")

      assert has_element?(lv, "#widget-cache-uploads")
      assert has_element?(lv, "#widget-cache-downloads")
      assert has_element?(lv, "#widget-cache-hit-rate")
    end
  end
end
