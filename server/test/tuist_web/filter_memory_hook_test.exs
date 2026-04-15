defmodule TuistWeb.FilterMemoryHookTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.FilterMemory
  alias TuistWeb.FilterMemoryHook

  describe "with_memory/3" do
    test "returns path unchanged when the key is missing" do
      assert FilterMemoryHook.with_memory("/builds", %{}, "builds") == "/builds"
    end

    test "returns path unchanged when the stored value is nil" do
      assert FilterMemoryHook.with_memory("/builds", %{"builds" => nil}, "builds") == "/builds"
    end

    test "returns path unchanged when the stored value is an empty string" do
      assert FilterMemoryHook.with_memory("/builds", %{"builds" => ""}, "builds") == "/builds"
    end

    test "appends the stored query string when present" do
      assert FilterMemoryHook.with_memory("/builds", %{"builds" => "scheme=App"}, "builds") ==
               "/builds?scheme=App"
    end
  end

  describe "hook behavior" do
    test "remembers a tracked list route's query on mount and restores it on the next visit",
         %{conn: conn, organization: organization, project: project, user: user} do
      tab_id = "tab-#{System.unique_integer([:positive])}"

      conn_with_tab = put_connect_params(conn, %{"tab_id" => tab_id})

      {:ok, _lv, _html} =
        live(
          conn_with_tab,
          ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_scheme_op===&filter_scheme_val=App"
        )

      assert %{"build-runs" => query} =
               FilterMemory.get_all(user.id, tab_id)

      decoded = URI.decode_query(query)
      assert decoded["filter_scheme_op"] == "=="
      assert decoded["filter_scheme_val"] == "App"
    end

    test "ignores untracked routes (no cache entry written)",
         %{conn: conn, organization: organization, project: project, user: user} do
      tab_id = "tab-#{System.unique_integer([:positive])}"

      conn_with_tab = put_connect_params(conn, %{"tab_id" => tab_id})

      {:ok, _lv, _html} =
        live(conn_with_tab, ~p"/#{organization.account.name}/#{project.name}/settings")

      assert FilterMemory.get_all(user.id, tab_id) == %{}
    end

    test "does not write to the cache when no tab_id connect param is supplied",
         %{conn: conn, organization: organization, project: project, user: user} do
      {:ok, _lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_scheme_op===&filter_scheme_val=App"
        )

      assert FilterMemory.get_all(user.id, "any-tab") == %{}
    end
  end
end
