defmodule TuistWeb.ProjectSitemapControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "advertises bounded project sitemap pages", %{conn: conn} do
    stub(Projects, :public_projects_count, fn -> 1001 end)
    xml = conn |> get("/sitemap-projects.xml") |> response(200)

    assert xml =~ "<sitemapindex"
    assert xml =~ "/sitemaps/projects/1.xml</loc>"
    assert xml =~ "/sitemaps/projects/2.xml</loc>"
    refute xml =~ "/sitemaps/projects/3.xml"
  end

  test "includes only public project roots, including those under private accounts", %{conn: conn} do
    public = ProjectsFixtures.project_fixture(visibility: :public)
    private = ProjectsFixtures.project_fixture(visibility: :private)
    public = Repo.preload(public, :account)
    private = Repo.preload(private, :account)
    conn = get(conn, "/sitemaps/projects/1.xml")
    xml = response(conn, 200)

    assert xml =~ "<urlset"
    assert xml =~ "<loc>#{Tuist.Environment.app_url(path: "/#{public.account.name}/#{public.name}")}</loc>"
    refute xml =~ Tuist.Environment.app_url(path: "/#{private.account.name}/#{private.name}")
    refute xml =~ "/settings"
    refute xml =~ "<lastmod>"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
  end

  test "excludes SSO redirects but includes public accounts with anonymous access", %{conn: conn} do
    organization =
      AccountsFixtures.organization_fixture(
        sso_provider: :okta,
        sso_organization_id: "example.okta.com",
        oauth2_client_id: "client-id",
        oauth2_client_secret: "client-secret"
      )

    organization |> Ecto.Changeset.change(sso_enforced: true) |> Repo.update!()
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id, visibility: :public)
    path = "/#{organization.account.name}/#{project.name}"

    assert Projects.public_projects_count() == 0
    refute conn |> get("/sitemaps/projects/1.xml") |> response(200) =~ path

    organization.account |> Ecto.Changeset.change(visibility: :public) |> Repo.update!()
    assert Projects.public_projects_count() == 1
    assert conn |> get("/sitemaps/projects/1.xml") |> response(200) =~ path
  end

  test "uses a bounded query for each page", %{conn: conn} do
    expect(Projects, :public_project_handles, fn 2, 1000 -> [%{account: "tuist", project: "tuist"}] end)
    assert conn |> get("/sitemaps/projects/2.xml") |> response(200) =~ "/tuist/tuist</loc>"
  end

  test "rejects malformed and empty out-of-range pages", %{conn: conn} do
    stub(Projects, :public_project_handles, fn _, _ -> [] end)

    for page <- ["0.xml", "-1.xml", "1", "garbage.xml", "1000000.xml", "2.xml"] do
      assert_error_sent 404, fn -> get(conn, "/sitemaps/projects/#{page}") end
    end

    assert conn |> get("/sitemaps/projects/1.xml") |> response(200) =~ "<urlset"
  end
end
