defmodule TuistWeb.ProjectLogoControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "show/2" do
    test "returns 404 when the project has no logo", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/logo")

      assert conn.status == 404
    end

    test "streams the logo binary with the stored content type", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      binary = "png-bytes"

      stub(Tuist.Storage, :put_object, fn _key, _binary, :project_logos -> :ok end)
      {:ok, project} = Projects.set_project_logo(project, binary, "image/png")

      stub(Tuist.Storage, :get_object, fn key, :project_logos ->
        assert key == project.logo_storage_key
        {:ok, binary}
      end)

      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/logo")

      assert conn.status == 200
      assert conn.resp_body == binary
      assert get_resp_header(conn, "content-type") == ["image/png"]
    end

    test "returns 404 for a project that does not exist", %{conn: conn} do
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        get(conn, ~p"/nobody/nothing/logo")
      end
    end
  end
end
