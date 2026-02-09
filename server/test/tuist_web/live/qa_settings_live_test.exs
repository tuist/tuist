defmodule TuistWeb.QASettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  describe "close_edit_launch_argument_modal" do
    test "handles dismiss without id param", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/qa")

      assert render_click(lv, "close_edit_launch_argument_modal", %{})
    end
  end

  describe "delete_launch_argument_group" do
    test "handles non-existent launch argument group", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/qa")

      assert render_click(lv, "delete_launch_argument_group", %{"id" => Ecto.UUID.generate()})
    end
  end

  describe "update_launch_argument_group" do
    test "handles non-existent launch argument group", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/qa")

      assert render_click(lv, "update_launch_argument_group", %{
               "id" => Ecto.UUID.generate(),
               "launch_argument_group" => %{"name" => "test", "value" => "--test"}
             })
    end
  end
end
