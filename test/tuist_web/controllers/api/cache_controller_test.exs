defmodule TuistWeb.API.CacheControllerTest do
  alias Tuist.CacheActionItems
  alias Tuist.CacheActionItems.CacheActionItem
  alias Tuist.Repo
  alias Tuist.CommandEvents
  alias Tuist.AccountsFixtures
  alias TuistWeb.Authentication
  alias Tuist.Accounts
  alias Tuist.ProjectsFixtures
  alias Tuist.Storage
  use TuistWeb.ConnCase, async: true
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
    object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

    CommandEvents.create_cache_event(%{
      project_id: project.id,
      name: name,
      event_type: :upload,
      size: 1024,
      hash: hash
    })

    Storage
    |> expect(:generate_download_url, fn ^object_key, _ ->
      download_url
    end)

    conn =
      conn
      |> Authentication.put_current_project(project)

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

    cache_event = CommandEvents.get_cache_event(%{hash: hash, event_type: :download})
    assert cache_event.size == 1024
  end

  describe "GET /api/projects/:account_handle/:project_handle/cache/ac/:hash" do
    test "returns cache action item", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"

      CacheActionItems.create_cache_action_item(%{
        hash: hash,
        project: project
      })

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/cache/ac/hash")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "hash" => "hash"
             }
    end

    test "returns not found error when the cache action item does not exist", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/cache/ac/hash")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{"message" => "The item doesn't exist in the cache."}
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/cache/:category" do
    test "creates a cache action item", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/cache/ac",
          %{
            hash: "hash"
          }
        )

      # Then
      cache_action_item = Repo.one(CacheActionItem)
      response = json_response(conn, :created)

      assert response == %{
               "hash" => "hash"
             }

      assert cache_action_item.hash == response["hash"]
    end

    test "returns bad request if the cache action item already exists", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> Authentication.put_current_user(user)

      hash = "hash"

      CacheActionItems.create_cache_action_item(%{
        hash: hash,
        project: project
      })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/cache/ac",
          %{
            hash: "hash"
          }
        )

      # Then
      response = json_response(conn, :bad_request)

      assert response == %{
               "message" => "Cache action item already exists."
             }
    end
  end

  describe "POST /api/cache/multipart/start" do
    test "starts multipart upload", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "12344"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      Storage
      |> expect(:multipart_start, fn ^object_key ->
        {:ok, upload_id}
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> post(
          ~p"/api/cache/multipart/start?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}"
        )

      # # Then
      response = json_response(conn, 200)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end

    test "starts multipart upload when it returns a raw error", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      Storage
      |> expect(:multipart_start, fn ^object_key ->
        {:error, {:raw, "error"}}
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> post(
          ~p"/api/cache/multipart/start?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}"
        )

      # # Then
      response = json_response(conn, :internal_server_error)
      assert response["message"] == "error"
    end

    test "starts multipart upload when it returns an http error", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      Storage
      |> expect(:multipart_start, fn ^object_key ->
        {:error, {:http, 502, "error"}}
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> post(
          ~p"/api/cache/multipart/start?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}"
        )

      # # Then
      response = json_response(conn, 502)
      assert response["message"] == "error"
    end
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
    object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

    Storage
    |> expect(:multipart_generate_url, fn ^object_key,
                                          ^upload_id,
                                          ^part_number,
                                          [expires_in: _] ->
      upload_url
    end)

    conn =
      conn
      |> Authentication.put_current_project(project)

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

  describe "POST /api/cache/multipart/complete" do
    test "completes a multipart upload", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      Storage
      |> expect(:multipart_complete_upload, fn ^object_key,
                                               ^upload_id,
                                               [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        :ok
      end)

      Storage
      |> expect(:get_object_size, fn ^object_key ->
        {:ok, 1024}
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

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

      cache_event = CommandEvents.get_cache_event(%{hash: hash, event_type: :upload})
      assert cache_event.size == 1024
    end

    test "returns an error if the completion of the multipart upload fails with a http error", %{
      conn: conn
    } do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      Storage
      |> expect(:multipart_complete_upload, fn ^object_key,
                                               ^upload_id,
                                               [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        {:error, {:http, 500, "error"}}
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/cache/multipart/complete?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&upload_id=#{upload_id}",
          parts: parts
        )

      # Then
      response = json_response(conn, 500)
      assert response["message"] == "error"
    end

    test "returns an error if the completion of the multipart upload fails with a raw error", %{
      conn: conn
    } do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      Storage
      |> expect(:multipart_complete_upload, fn ^object_key,
                                               ^upload_id,
                                               [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        {:error, {:raw, "error"}}
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/cache/multipart/complete?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&upload_id=#{upload_id}",
          parts: parts
        )

      # Then
      response = json_response(conn, :internal_server_error)
      assert response["message"] == "error"
    end

    test "completes a multipart upload when an item was uploaded before", %{conn: conn} do
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
      |> stub(:multipart_complete_upload, fn _, _, _ -> :ok end)

      Storage
      |> stub(:get_object_size, fn _ -> {:ok, 1024} end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      CommandEvents.create_cache_event(%{
        hash: hash,
        name: name,
        event_type: :upload,
        project_id: project.id,
        size: 1024
      })

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

      cache_event = CommandEvents.get_cache_event(%{hash: hash, event_type: :upload})
      assert cache_event.size == 1024
    end

    test "returns an error if obtaining the size returns an HTTP error", %{conn: conn} do
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
      |> stub(:multipart_complete_upload, fn _, _, _ -> :ok end)

      Storage
      |> stub(:get_object_size, fn _ -> {:error, {:http, 500, "Test error"}} end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      CommandEvents.create_cache_event(%{
        hash: hash,
        name: name,
        event_type: :upload,
        project_id: project.id,
        size: 1024
      })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/cache/multipart/complete?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&upload_id=#{upload_id}",
          parts: parts
        )

      # Then
      response = json_response(conn, 500)
      assert response["message"] == "Test error"
    end

    test "returns an error if obtaining the size returns a raw error", %{conn: conn} do
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
      |> stub(:multipart_complete_upload, fn _, _, _ -> :ok end)

      Storage
      |> stub(:get_object_size, fn _ -> {:error, {:raw, "Test error"}} end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      CommandEvents.create_cache_event(%{
        hash: hash,
        name: name,
        event_type: :upload,
        project_id: project.id,
        size: 1024
      })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/cache/multipart/complete?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&upload_id=#{upload_id}",
          parts: parts
        )

      # Then
      response = json_response(conn, :internal_server_error)
      assert response["message"] == "Test error"
    end
  end

  describe "PUT /api/projects/:account_handle/:project_handle/cache/clean" do
    test "given project is cleaned", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      builds_prefix = "#{account.name}/#{project.name}/builds"
      tests_prefix = "#{account.name}/#{project.name}/tests"

      Storage
      |> expect(:delete_all_objects, fn ^builds_prefix ->
        :ok
      end)

      Storage
      |> expect(:delete_all_objects, fn ^tests_prefix ->
        :ok
      end)

      hash = "hash"

      CacheActionItems.create_cache_action_item(%{
        hash: hash,
        project: project
      })

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

      # Then
      response = response(conn, :no_content)

      assert response == ""
      assert CacheActionItems.get_cache_action_item(%{project: project, hash: hash}) == nil
    end

    test "given organization project is cleaned", %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      user = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user, organization)
      builds_prefix = "#{account.name}/#{project.name}/builds"
      tests_prefix = "#{account.name}/#{project.name}/tests"

      Storage
      |> expect(:delete_all_objects, fn ^builds_prefix ->
        :ok
      end)

      Storage
      |> expect(:delete_all_objects, fn ^tests_prefix ->
        :ok
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

      # Then
      response = response(conn, :no_content)

      assert response == ""
    end

    test "forbidden error is returned when user doesn't have permission to clean the project cache",
         %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      user =
        AccountsFixtures.user_fixture()
        |> Repo.preload(:account)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "#{user.account.name} is not authorized to update cache"
    end

    test "not found error is returned when project doesn't exist",
         %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put(~p"/api/projects/#{account.name}/non-existing-project/cache/clean")

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The project #{account.name}/non-existing-project was not found."
    end
  end
end
