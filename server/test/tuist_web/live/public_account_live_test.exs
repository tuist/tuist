defmodule TuistWeb.PublicAccountLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "public-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    {:ok, account} = Accounts.update_account_visibility(account, :public)

    %{user: user, account: account}
  end

  describe "signed-out visitors on a public account" do
    test "can read the runners dashboards", %{conn: conn, account: account} do
      for path <- [
            ~p"/#{account.name}/runners",
            ~p"/#{account.name}/runners/workflows",
            ~p"/#{account.name}/runners/jobs"
          ] do
        assert {:ok, _view, _html} = live(conn, path)
      end
    end

    test "can read the projects list", %{conn: conn, account: account} do
      assert {:ok, _view, _html} = live(conn, ~p"/#{account.name}/projects")
    end

    test "see the account's public projects but not its private ones", %{conn: conn, account: account} do
      ProjectsFixtures.project_fixture(account_id: account.id, name: "open-source", visibility: :public)
      ProjectsFixtures.project_fixture(account_id: account.id, name: "closed-source", visibility: :private)

      {:ok, _view, html} = live(conn, ~p"/#{account.name}/projects")

      assert html =~ "open-source"
      refute html =~ "closed-source"
    end

    test "are not offered the create-project form", %{conn: conn, account: account} do
      ProjectsFixtures.project_fixture(account_id: account.id, name: "open-source", visibility: :public)

      {:ok, _view, html} = live(conn, ~p"/#{account.name}/projects")

      refute html =~ "create-project-form"
    end

    test "are redirected to log in for members, webhooks, cache, billing, and settings", %{
      conn: conn,
      account: account
    } do
      for path <- [
            ~p"/#{account.name}/members",
            ~p"/#{account.name}/webhooks",
            ~p"/#{account.name}/cache",
            ~p"/#{account.name}/billing",
            ~p"/#{account.name}/settings",
            ~p"/#{account.name}/settings/tokens",
            ~p"/#{account.name}/runners/profiles"
          ] do
        assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, path)
      end
    end
  end

  describe "signed-out visitors on a private account" do
    setup %{account: account} do
      {:ok, account} = Accounts.update_account_visibility(account, :private)
      %{account: account}
    end

    test "are redirected to log in for the runners dashboards", %{conn: conn, account: account} do
      for path <- [
            ~p"/#{account.name}/runners",
            ~p"/#{account.name}/runners/workflows",
            ~p"/#{account.name}/runners/jobs",
            ~p"/#{account.name}/projects"
          ] do
        assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, path)
      end
    end
  end

  describe "members of a public account" do
    test "still see the account's private projects", %{conn: conn, user: user, account: account} do
      ProjectsFixtures.project_fixture(account_id: account.id, name: "open-source", visibility: :public)
      ProjectsFixtures.project_fixture(account_id: account.id, name: "closed-source", visibility: :private)

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/#{account.name}/projects")

      assert html =~ "open-source"
      assert html =~ "closed-source"
    end

    test "are still offered the create-project form", %{conn: conn, user: user, account: account} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/#{account.name}/projects")

      assert html =~ "create-project-form"
    end

    test "still reach the admin dashboards", %{conn: conn, user: user, account: account} do
      conn = log_in_user(conn, user)

      assert {:ok, _view, _html} = live(conn, ~p"/#{account.name}/members")
      assert {:ok, _view, _html} = live(conn, ~p"/#{account.name}/settings")
    end
  end
end
