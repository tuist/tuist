defmodule TuistWeb.CreateOrganizationLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  describe "Create organization page" do
    test "renders create organization page", %{conn: conn} do
      user = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/organizations/new")

      assert html =~ "Create a new organization"
    end

    test "handles organization creation form submission with account key", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/organizations/new")

      lv
      |> form("#create-project-form",
        account: %{name: "Test Organization"}
      )
      |> render_submit()
    end
  end
end
