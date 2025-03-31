defmodule TuistWeb.API.CacheControllerTest do
  alias Tuist.CacheActionItems
  alias Tuist.CacheActionItems.CacheActionItem
  alias Tuist.Repo
  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias Tuist.Storage
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  setup do
    cache = UUIDv7.generate() |> String.to_atom()
    {:ok, _} = Cachex.start_link(name: cache)
    %{cache: cache}
  end

  describe "GET /api/cache" do
    test "returns download url", %{conn: conn, cache: cache} do
      # Given
      project = %{id: project_id} = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      size = 1024
      project_slug = "#{account.name}/#{project.name}"
      cache_category = "builds"
      download_url = "https://tuist.dev/download/1234"
      object_key = "#{project_slug}/#{cache_category}/#{hash}/#{name}"
      date = ~N[2024-04-30 10:20:30Z]

      NaiveDateTime |> stub(:utc_now, fn :second -> date end)

      Storage
      |> expect(:generate_download_url, fn ^object_key, _ ->
        download_url
      end)

      Storage |> expect(:object_exists?, fn ^object_key -> true end)
      Storage |> expect(:get_object_size, fn ^object_key -> size end)

      Tuist.API.Pipeline
      |> expect(:async_push, fn {:cache_event,
                                 %{
                                   event_type: :download,
                                   hash: ^hash,
                                   name: ^name,
                                   project_id: ^project_id,
                                   size: ^size,
                                   created_at: ^date,
                                   updated_at: ^date
                                 }} ->
        :ok
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> get(~p"/api/cache",
          hash: hash,
          name: name,
          project_id: project_slug,
          cache_category: cache_category
        )

      # Then
      response = json_response(conn, 200)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["url"] == download_url
      assert response_data["expires_at"] != nil
    end

    test "returns download url with downcased full handle", %{conn: conn, cache: cache} do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "MyAccount", preload: [:account])

      project =
        %{id: project_id} =
        ProjectsFixtures.project_fixture(
          name: "MyProject",
          account_id: organization.account.id
        )

      hash = "hash"
      name = "name"
      full_handle = "MyAccount/MyProject"
      cache_category = "builds"
      download_url = "https://tuist.dev/download/1234"
      object_key = "myaccount/myproject/#{cache_category}/#{hash}/#{name}"
      size = 1024
      date = ~N[2024-04-30 10:20:30Z]

      NaiveDateTime |> stub(:utc_now, fn :second -> date end)

      Storage
      |> expect(:generate_download_url, fn ^object_key, _ ->
        download_url
      end)

      Storage |> expect(:object_exists?, fn ^object_key -> true end)
      Storage |> expect(:get_object_size, fn ^object_key -> size end)

      Tuist.API.Pipeline
      |> expect(:async_push, fn {:cache_event,
                                 %{
                                   event_type: :download,
                                   hash: ^hash,
                                   name: ^name,
                                   project_id: ^project_id,
                                   size: ^size,
                                   created_at: ^date,
                                   updated_at: ^date
                                 }} ->
        :ok
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> get(~p"/api/cache",
          hash: hash,
          name: name,
          project_id: full_handle,
          cache_category: cache_category
        )

      # Then
      response = json_response(conn, 200)
      assert response["data"]["url"] == download_url
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/cache/ac/:hash" do
    test "returns cache action item", %{conn: conn, cache: cache} do
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
        |> assign(:cache, cache)
        |> get(~p"/api/projects/#{account.name}/#{project.name}/cache/ac/hash")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "hash" => "hash"
             }
    end

    test "returns not found error when the cache action item does not exist", %{
      conn: conn,
      cache: cache
    } do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> get(~p"/api/projects/#{account.name}/#{project.name}/cache/ac/hash")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{"message" => "The item doesn't exist in the cache."}
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/cache/:category" do
    test "creates a cache action item", %{conn: conn, cache: cache} do
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
        |> assign(:cache, cache)
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

    test "returns created with the cache action item when the CLI version is 4.28.0", %{
      conn: conn,
      cache: cache
    } do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("x-tuist-cli-version", "4.28.0")

      CacheActionItems.create_cache_action_item(%{
        hash: "hash",
        project: project
      })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:cache, cache)
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

    test "returns ok if the cache action item already exists", %{conn: conn, cache: cache} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> Authentication.put_current_user(user)

      hash = "hash"

      cache_action_item =
        CacheActionItems.create_cache_action_item(%{
          hash: hash,
          project: project
        })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:cache, cache)
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/cache/ac",
          %{
            hash: "hash"
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "hash" => "hash"
             }

      assert cache_action_item.hash == response["hash"]
    end
  end

  describe "POST /api/cache/multipart/start" do
    test "starts multipart upload", %{conn: conn, cache: cache} do
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
        upload_id
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> post(
          ~p"/api/cache/multipart/start?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}"
        )

      # # Then
      response = json_response(conn, 200)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end
  end

  test "POST /api/cache/multipart/generate-url", %{conn: conn, cache: cache} do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    hash = "hash"
    name = "name"
    project_id = "#{account.name}/#{project.name}"
    cache_category = "builds"
    upload_id = "1234"
    part_number = "3"
    upload_url = "https://tuist.dev/upload/1234"
    object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

    Storage
    |> expect(:multipart_generate_url, fn ^object_key,
                                          ^upload_id,
                                          ^part_number,
                                          [expires_in: _, content_length: 20] ->
      upload_url
    end)

    conn =
      conn
      |> Authentication.put_current_project(project)

    # When
    conn =
      conn
      |> assign(:cache, cache)
      |> post(
        ~p"/api/cache/multipart/generate-url?hash=#{hash}&content_length=20&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&part_number=#{part_number}&upload_id=#{upload_id}"
      )

    # Then
    response = json_response(conn, 200)
    assert response["status"] == "success"
    response_data = response["data"]
    assert response_data["url"] == upload_url
  end

  describe "POST /api/cache/multipart/complete" do
    test "completes a multipart upload", %{conn: conn, cache: cache} do
      # Given
      project = %{id: project_id} = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_slug = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"
      object_key = "#{project_slug}/#{cache_category}/#{hash}/#{name}"
      size = 1024
      date = ~N[2024-04-30 10:20:30Z]

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      NaiveDateTime |> stub(:utc_now, fn :second -> date end)

      Storage
      |> expect(:multipart_complete_upload, fn ^object_key,
                                               ^upload_id,
                                               [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        :ok
      end)

      Storage
      |> expect(:get_object_size, fn ^object_key ->
        size
      end)

      Tuist.API.Pipeline
      |> expect(:async_push, fn {:cache_event,
                                 %{
                                   name: ^name,
                                   size: ^size,
                                   hash: ^hash,
                                   created_at: ^date,
                                   updated_at: ^date,
                                   project_id: ^project_id,
                                   event_type: :upload
                                 }} ->
        :ok
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:cache, cache)
        |> post(
          ~p"/api/cache/multipart/complete?hash=#{hash}&name=#{name}&project_id=#{project_slug}&cache_category=#{cache_category}&upload_id=#{upload_id}",
          parts: parts
        )

      # Then
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"] == %{}
    end

    test "completes a multipart upload when an item was uploaded before", %{
      conn: conn,
      cache: cache
    } do
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
        |> assign(:cache, cache)
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
  end

  describe "PUT /api/projects/:account_handle/:project_handle/cache/clean" do
    test "given project is cleaned", %{conn: conn, cache: cache} do
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
        |> assign(:cache, cache)
        |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

      # Then
      response = response(conn, :no_content)

      assert response == ""
      assert CacheActionItems.get_cache_action_item(%{project: project, hash: hash}) == nil
    end

    test "given organization project is cleaned", %{conn: conn, cache: cache} do
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
        |> assign(:cache, cache)
        |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

      # Then
      response = response(conn, :no_content)

      assert response == ""
    end

    test "forbidden error is returned when user doesn't have permission to clean the project cache",
         %{conn: conn, cache: cache} do
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
        |> assign(:cache, cache)
        |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "#{user.account.name} is not authorized to update cache"
    end

    test "not found error is returned when project doesn't exist",
         %{conn: conn, cache: cache} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> put(~p"/api/projects/#{account.name}/non-existing-project/cache/clean")

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The project #{account.name}/non-existing-project was not found."
    end
  end
end
