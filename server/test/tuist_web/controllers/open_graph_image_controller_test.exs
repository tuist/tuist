defmodule TuistWeb.OpenGraphImageControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.ConnTest
  import Plug.Conn

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.OpenGraphImageRenderer
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Storage
  alias TuistWeb.Helpers.OpenGraph

  @endpoint TuistWeb.Endpoint

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    %{conn: build_conn()}
  end

  test "serves a cached image without rendering it again", %{conn: conn} do
    %{key: key, object_key: object_key, path: path} = image_request()

    expect(Storage, :object_exists?, fn ^object_key, :open_graph_images -> true end)
    expect(Storage, :get_object, fn ^object_key, :open_graph_images -> {:ok, "cached-image"} end)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :ok) == "cached-image"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "etag") == [~s("#{key}")]
  end

  test "renders and stores an image on the first request", %{conn: conn} do
    %{object_key: object_key, path: path} = image_request()

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)
    expect(OpenGraphImageRenderer, :render, fn _html, "About Tuist" -> {:ok, "generated-image"} end)
    expect(Storage, :put_object, fn ^object_key, "generated-image", :open_graph_images -> :ok end)
    expect(Storage, :get_object, fn ^object_key, :open_graph_images -> {:ok, "generated-image"} end)

    conn = get(conn, path)

    assert response(conn, :ok) == "generated-image"
  end

  test "does not resolve an image when the signature is missing", %{conn: conn} do
    %{path: path} = image_request()
    path = path |> URI.parse() |> Map.fetch!(:path)

    reject(&Storage.object_exists?/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :not_found) == ""
  end

  test "does not resolve an image when the signature is invalid", %{conn: conn} do
    %{path: path} = image_request()
    path = String.replace(path, "token=", "token=invalid", global: false)

    reject(&Storage.object_exists?/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :not_found) == ""
  end

  test "does not resolve an image when the signature is not a string", %{conn: conn} do
    %{path: path} = image_request()
    uri = URI.parse(path)

    image_params =
      uri.query
      |> URI.decode_query()
      |> Map.delete("token")
      |> URI.encode_query()

    path = uri.path <> "?" <> image_params <> "&token[]=invalid"

    reject(&Storage.object_exists?/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :not_found) == ""
  end

  test "does not resolve an image when the signed token is altered", %{conn: conn} do
    %{path: path} = image_request()
    path = path <> "tampered"

    reject(&Storage.object_exists?/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :not_found) == ""
  end

  test "does not read storage when the path key does not match the signed variables", %{conn: conn} do
    %{key: key, path: path} = image_request()
    path = String.replace(path, key, String.duplicate("0", 64), global: false)

    reject(&Storage.object_exists?/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :not_found) == ""
  end

  test "serves the rendered image transiently when caching it fails", %{conn: conn} do
    %{object_key: object_key, path: path} = image_request()

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)
    expect(OpenGraphImageRenderer, :render, fn _html, "About Tuist" -> {:ok, "rendered-image"} end)

    expect(Storage, :put_object, fn ^object_key, "rendered-image", :open_graph_images ->
      {:error, :storage_down}
    end)

    reject(&Storage.get_object/2)

    conn = get(conn, path)

    assert response(conn, :ok) == "rendered-image"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
    assert get_resp_header(conn, "etag") == []
  end

  test "serves a fallback image transiently without persisting it", %{conn: conn} do
    %{object_key: object_key, path: path} = image_request()

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)
    expect(OpenGraphImageRenderer, :render, fn _html, "About Tuist" -> {:fallback, "fallback-image"} end)
    reject(&Storage.put_object/3)
    reject(&Storage.get_object/2)

    conn = get(conn, path)

    assert response(conn, :ok) == "fallback-image"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
    assert get_resp_header(conn, "etag") == []
  end

  test "returns service unavailable when rendering fails", %{conn: conn} do
    %{object_key: object_key, path: path} = image_request()

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)
    expect(OpenGraphImageRenderer, :render, fn _html, "About Tuist" -> {:error, :timeout} end)

    conn = get(conn, path)

    assert response(conn, :service_unavailable) == ""
  end

  test "returns service unavailable when reading the cached image fails", %{conn: conn} do
    %{object_key: object_key, path: path} = image_request()

    expect(Storage, :object_exists?, fn ^object_key, :open_graph_images -> true end)
    expect(Storage, :get_object, fn ^object_key, :open_graph_images -> {:error, :storage_down} end)

    conn = get(conn, path)

    assert response(conn, :service_unavailable) == ""
    refute get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  test "honors the entity tag without downloading the cached image", %{conn: conn} do
    %{key: key, object_key: object_key, path: path} = image_request()

    expect(Storage, :object_exists?, fn ^object_key, :open_graph_images -> true end)
    reject(&Storage.get_object/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = conn |> put_req_header("if-none-match", ~s("#{key}")) |> get(path)

    assert response(conn, :not_modified) == ""
  end

  test "rechecks project visibility before serving an already-cached image", %{conn: conn} do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    expect(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)
    path = OpenGraph.project_image_assigns(project, title: "Builds")[:head_image]

    expect(Projects, :get_project_by_slug, fn ^slug -> {:ok, %{project | visibility: :private}} end)

    reject(&Storage.object_exists?/2)
    reject(&Storage.get_object/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :not_found) == ""
  end

  test "requires revalidation for a cached public-project image", %{conn: conn} do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    expect(Projects, :get_project_by_slug, 2, fn ^slug -> {:ok, project} end)
    path = OpenGraph.project_image_assigns(project, title: "Builds")[:head_image]
    uri = URI.parse(path)
    key = Path.basename(uri.path, ".jpg")
    object_key = "open-graph-images/#{key}.jpg"

    expect(Storage, :object_exists?, fn ^object_key, :open_graph_images -> true end)
    expect(Storage, :get_object, fn ^object_key, :open_graph_images -> {:ok, "cached-project-image"} end)

    conn = get(conn, path)

    assert response(conn, :ok) == "cached-project-image"
    assert get_resp_header(conn, "cache-control") == ["public, no-cache"]
  end

  test "does not cache a project card when its configured logo cannot be read", %{conn: conn} do
    project = %{public_project() | logo_storage_key: "project-logos/42/missing.png"}
    slug = "#{project.account.name}/#{project.name}"
    expect(Projects, :get_project_by_slug, 2, fn ^slug -> {:ok, project} end)
    path = OpenGraph.project_image_assigns(project, title: "Builds")[:head_image]
    uri = URI.parse(path)
    key = Path.basename(uri.path, ".jpg")
    object_key = "open-graph-images/#{key}.jpg"

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)

    expect(Storage, :get_object, fn "project-logos/" <> _rest, :project_logos ->
      {:error, :not_found}
    end)

    reject(&Storage.put_object/3)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert response(conn, :service_unavailable) == ""
  end

  test "does not render on-premise, forwarding the request away instead", %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> false end)
    %{path: path} = image_request()

    reject(&Storage.object_exists?/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, path)

    assert conn.status in [301, 302]
    assert conn.halted
  end

  defp image_request do
    path =
      OpenGraph.image_path(:marketing,
        title: "About Tuist",
        icon: "static/marketing/images/about/logo.webp"
      )

    uri = URI.parse(path)
    key = Path.basename(uri.path, ".jpg")

    %{
      key: key,
      object_key: "open-graph-images/#{key}.jpg",
      path: path
    }
  end

  defp public_project do
    %Project{
      id: 42,
      name: "tuist",
      visibility: :public,
      account: %Account{name: "tuist"}
    }
  end
end
