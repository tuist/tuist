defmodule TuistCloudWeb.CacheControllerTest do
  alias TuistCloudWeb.Authentication
  alias TuistCloud.Accounts
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Storage
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  test "GET /api/cache", %{conn: conn} do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    hash = "hash"
    name = "name"
    project_id = "#{account.name}/#{project.name}"
    cache_category = "builds"
    download_url = "https://cloud.tuist.io/download/1234"

    Storage
    |> expect(:generate_download_url, fn %{
                                           hash: ^hash,
                                           name: ^name,
                                           project_slug: ^project_id,
                                           cache_category: ^cache_category
                                         },
                                         _ ->
      download_url
    end)

    conn =
      conn
      |> Authentication.put_authenticated_project(project)

    # When
    conn =
      conn
      |> get(~p"/api/cache",
        hash: hash,
        name: name,
        project_id: project_id,
        cache_category: cache_category
      )

    # Then
    response = json_response(conn, 200)
    assert response["status"] == "success"
    response_data = response["data"]
    assert response_data["url"] == download_url
    assert response_data["expires_at"] != nil
  end

  test "POST /api/cache/multipart/start", %{conn: conn} do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    hash = "hash"
    name = "name"
    project_id = "#{account.name}/#{project.name}"
    cache_category = "builds"
    upload_id = "12344"

    Storage
    |> expect(:multipart_start, fn %{
                                     hash: ^hash,
                                     name: ^name,
                                     project_slug: ^project_id,
                                     cache_category: ^cache_category
                                   } ->
      upload_id
    end)

    conn =
      conn
      |> Authentication.put_authenticated_project(project)

    # When
    conn =
      conn
      |> post(
        ~p"/api/cache/multipart/start?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}"
      )

    # Then
    response = json_response(conn, 200)
    assert response["status"] == "success"
    response_data = response["data"]
    assert response_data["upload_id"] == upload_id
  end

  test "POST /api/cache/multipart/generate-url", %{conn: conn} do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    hash = "hash"
    name = "name"
    project_id = "#{account.name}/#{project.name}"
    cache_category = "builds"
    upload_id = "1234"
    part_number = "3"
    upload_url = "https://cloud.tuist.io/upload/1234"

    Storage
    |> expect(:generate_multipart_upload_url, fn %{
                                                   hash: ^hash,
                                                   name: ^name,
                                                   project_slug: ^project_id,
                                                   cache_category: ^cache_category
                                                 },
                                                 ^upload_id,
                                                 ^part_number,
                                                 [expires_in: _] ->
      upload_url
    end)

    conn =
      conn
      |> Authentication.put_authenticated_project(project)

    # When
    conn =
      conn
      |> post(
        ~p"/api/cache/multipart/generate-url?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&part_number=#{part_number}&upload_id=#{upload_id}"
      )

    # Then
    response = json_response(conn, 200)
    assert response["status"] == "success"
    response_data = response["data"]
    assert response_data["url"] == upload_url
  end

  test "POST /api/cache/multipart/complete", %{conn: conn} do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    hash = "hash"
    name = "name"
    project_id = "#{account.name}/#{project.name}"
    cache_category = "builds"
    upload_id = "1234"

    parts = [
      %{part_number: 1, etag: "etag1"},
      %{part_number: 2, etag: "etag2"},
      %{part_number: 3, etag: "etag3"}
    ]

    Storage
    |> expect(:complete_multipart_upload, fn %{
                                               hash: ^hash,
                                               name: ^name,
                                               project_slug: ^project_id,
                                               cache_category: ^cache_category
                                             },
                                             ^upload_id,
                                             [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
      :ok
    end)

    conn =
      conn
      |> Authentication.put_authenticated_project(project)

    # When
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/cache/multipart/complete?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&upload_id=#{upload_id}",
        parts: parts
      )

    # Then
    response = json_response(conn, 200)
    assert response["status"] == "success"
    assert response["data"] == %{}
  end
end
