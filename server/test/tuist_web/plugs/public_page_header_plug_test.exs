defmodule TuistWeb.Plugs.PublicPageHeaderPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Plugs.PublicPageHeaderPlug

  @header "x-tuist-public"

  setup do
    %{user: AccountsFixtures.user_fixture(preload: [:account])}
  end

  describe "mark_public_project_page/2" do
    test "sets the header when the project is public", %{conn: conn} do
      project =
        [visibility: :public]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name
          }
      }

      conn = PublicPageHeaderPlug.mark_public_project_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == ["1"]
    end

    test "does not set the header when the project is private", %{conn: conn} do
      project =
        [visibility: :private]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name
          }
      }

      conn = PublicPageHeaderPlug.mark_public_project_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == []
    end

    test "sets the header regardless of whether the current user is signed in", %{conn: conn, user: user} do
      project =
        [visibility: :public]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name
          }
      }

      conn =
        conn
        |> Plug.Conn.assign(:current_user, user)
        |> PublicPageHeaderPlug.mark_public_project_page([])

      assert Plug.Conn.get_resp_header(conn, @header) == ["1"]
    end

    test "does not set the header when the project cannot be found", %{conn: conn} do
      conn = %{
        conn
        | path_params: %{
            "account_handle" => "does-not-exist",
            "project_handle" => "nope"
          }
      }

      conn = PublicPageHeaderPlug.mark_public_project_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == []
    end
  end

  describe "mark_public_account_page/2" do
    test "sets the header when the account is public", %{conn: conn} do
      %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
      {:ok, _account} = Accounts.update_account_visibility(account, :public)

      conn = %{conn | path_params: %{"account_handle" => account.name}}

      conn = PublicPageHeaderPlug.mark_public_account_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == ["1"]
    end

    test "does not set the header when the account is private", %{conn: conn} do
      %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])

      conn = %{conn | path_params: %{"account_handle" => account.name}}

      conn = PublicPageHeaderPlug.mark_public_account_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == []
    end

    test "does not set the header when the account cannot be found", %{conn: conn} do
      conn = %{conn | path_params: %{"account_handle" => "does-not-exist"}}

      conn = PublicPageHeaderPlug.mark_public_account_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == []
    end
  end

  describe "mark_public_preview_page/2" do
    test "sets the header when the preview itself is public", %{conn: conn} do
      project =
        [visibility: :private]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview = AppBuildsFixtures.preview_fixture(project: project, visibility: :public)

      conn = %{conn | path_params: %{"id" => preview.id}}

      conn = PublicPageHeaderPlug.mark_public_preview_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == ["1"]
    end

    test "sets the header when the parent project is public", %{conn: conn} do
      project =
        [visibility: :public]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview = AppBuildsFixtures.preview_fixture(project: project)

      conn = %{conn | path_params: %{"id" => preview.id}}

      conn = PublicPageHeaderPlug.mark_public_preview_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == ["1"]
    end

    test "does not set the header when both the preview and the project are private", %{conn: conn} do
      project =
        [visibility: :private]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview = AppBuildsFixtures.preview_fixture(project: project, visibility: :private)

      conn = %{conn | path_params: %{"id" => preview.id}}

      conn = PublicPageHeaderPlug.mark_public_preview_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == []
    end

    test "does not set the header when the preview cannot be found", %{conn: conn} do
      conn = %{conn | path_params: %{"id" => UUIDv7.generate()}}

      conn = PublicPageHeaderPlug.mark_public_preview_page(conn, [])

      assert Plug.Conn.get_resp_header(conn, @header) == []
    end
  end
end
