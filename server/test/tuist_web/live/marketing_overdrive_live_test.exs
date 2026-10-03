defmodule TuistWeb.Marketing.MarketingOverdriveLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase, async: false

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup do
    account = AccountsFixtures.organization_fixture(name: "tuist", preload: [:account]).account
    %{account: account}
  end

  describe "GET /overdrive" do
    test "lists public curated forks", %{conn: conn, account: account} do
      ProjectsFixtures.project_fixture(account: account, name: "mise", visibility: :public, build_system: :once)

      {:ok, _lv, html} = live(conn, ~p"/overdrive")

      assert html =~ "Fork of jdx/mise"
      assert html =~ ~s(href="/overdrive/tuist/mise")
    end
  end

  describe "GET /overdrive/:account_handle/:project_handle" do
    test "renders the fork's page with its dashboard link and share card", %{conn: conn, account: account} do
      ProjectsFixtures.project_fixture(account: account, name: "mise", visibility: :public, build_system: :once)

      {:ok, _lv, html} = live(conn, ~p"/overdrive/tuist/mise")

      assert html =~ ~s(href="/tuist/mise")
      assert html =~ "https://github.com/jdx/mise"
      assert html =~ "/open-graph-images/"
    end

    test "is not found when the fork's project is private", %{conn: conn, account: account} do
      ProjectsFixtures.project_fixture(account: account, name: "mise", visibility: :private)

      assert_raise NotFoundError, fn -> live(conn, ~p"/overdrive/tuist/mise") end
    end
  end
end
