defmodule AtlasWeb.Plugs.PagesSubdomainTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Engineering.Pages
  alias Atlas.Repo
  alias Atlas.Users.User
  alias AtlasWeb.Plugs.PagesSubdomain

  defp user do
    email = "pages-sub-#{System.unique_integer([:positive])}@tuist.dev"

    %User{}
    |> User.changeset(%{email: email, name: "Pages Test"})
    |> Repo.insert!()
  end

  test "apex host falls through to the router", %{conn: conn} do
    result = conn |> Map.put(:host, "atlas.tuist.dev") |> PagesSubdomain.call([])
    refute result.halted
  end

  test "unknown subdomain returns 404 when the page does not exist", %{conn: conn} do
    author = user()

    conn =
      conn
      |> Map.put(:host, "missing-site.atlas.tuist.dev")
      |> Plug.Test.init_test_session(%{user_id: author.id})

    result = PagesSubdomain.call(conn, [])
    assert result.halted
    assert result.status == 404
  end

  test "known subdomain serves the site's index for an authenticated user", %{conn: conn} do
    author = user()
    {:ok, page} = Pages.create_page(%{"slug" => "welcome"}, author)

    Atlas.ObjectStorage
    |> stub(:presigned_put_url, fn _key, _opts -> {:ok, "https://example.test/put"} end)
    |> stub(:head_object, fn _key, _opts -> {:ok, %{status: 200, headers: [], body: ""}} end)

    {:ok, %{deploy: deploy}} =
      Pages.start_deploy(page, [%{"path" => "index.html", "size" => 12}], author)

    {:ok, _result} = Pages.finalize_deploy(deploy, author)

    Atlas.ObjectStorage
    |> stub(:get_object, fn _key, _opts ->
      {:ok, %{body: "<h1>welcome</h1>", content_type: "text/html; charset=utf-8", key: "x"}}
    end)

    conn =
      conn
      |> Map.put(:host, "welcome.atlas.tuist.dev")
      |> Map.put(:path_info, [])
      |> Plug.Test.init_test_session(%{user_id: author.id})

    result = PagesSubdomain.call(conn, [])
    assert result.halted
    assert result.status == 200
    assert result.resp_body =~ "welcome"
    assert get_resp_header(result, "content-type") == ["text/html; charset=utf-8"]
  end

  test "unauthenticated request redirects to /login", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "any.atlas.tuist.dev")
      |> Plug.Test.init_test_session(%{})

    result = PagesSubdomain.call(conn, [])
    assert result.halted
    assert result.status == 302
    assert get_resp_header(result, "location") == ["/login"]
  end
end
