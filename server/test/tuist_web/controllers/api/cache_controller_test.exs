defmodule TuistWeb.API.CacheControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.API.Pipeline
  alias Tuist.CacheActionItems
  alias Tuist.CacheActionItems.CacheActionItem
  alias Tuist.Projects.Workers.CleanProjectWorker
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)
    %{cache: cache}
  end

  describe "GET /api/cache/endpoints" do
    test "returns list of cache endpoints", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      expected_endpoints = [
        "https://cache-eu-central-test.tuist.dev",
        "https://cache-us-east-test.tuist.dev"
      ]

      stub(Tuist.Environment, :cache_endpoints, fn -> expected_endpoints end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cache/endpoints")

      # Then
      response = json_response(conn, 200)
      assert response["endpoints"] == expected_endpoints
    end

    test "returns default endpoints when account_handle is provided but account has no custom endpoints",
         %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      expected_endpoints = [
        "https://cache-eu-central-test.tuist.dev",
        "https://cache-us-east-test.tuist.dev"
      ]

      stub(Tuist.Environment, :cache_endpoints, fn -> expected_endpoints end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cache/endpoints?account_handle=#{account.name}")

      # Then
      response = json_response(conn, 200)
      assert response["endpoints"] == expected_endpoints
    end

    test "returns custom endpoints when account has custom endpoints configured",
         %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, _endpoint1} =
        Accounts.create_account_cache_endpoint(account, %{url: "https://custom-cache-1.example.com"})

      {:ok, _endpoint2} =
        Accounts.create_account_cache_endpoint(account, %{url: "https://custom-cache-2.example.com"})

      default_endpoints = [
        "https://cache-eu-central-test.tuist.dev",
        "https://cache-us-east-test.tuist.dev"
      ]

      stub(Tuist.Environment, :cache_endpoints, fn -> default_endpoints end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cache/endpoints?account_handle=#{account.name}")

      # Then
      response = json_response(conn, 200)

      assert Enum.sort(response["endpoints"]) ==
               Enum.sort(["https://custom-cache-1.example.com", "https://custom-cache-2.example.com"])
    end

    test "returns default endpoints when account_handle does not exist",
         %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      expected_endpoints = [
        "https://cache-eu-central-test.tuist.dev",
        "https://cache-us-east-test.tuist.dev"
      ]

      stub(Tuist.Environment, :cache_endpoints, fn -> expected_endpoints end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cache/endpoints?account_handle=nonexistent-account")

      # Then
      response = json_response(conn, 200)
      assert response["endpoints"] == expected_endpoints
    end
  end

  describe "GET /api/cache" do
    test "returns download url", %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_slug = "#{account.name}/#{project.name}"
      cache_category = "builds"
      download_url = "https://tuist.dev/download/1234"
      object_key = "#{project_slug}/#{cache_category}/#{hash}/#{name}"
      date = ~N[2024-04-30 10:20:30Z]

      stub(Tuist.Environment, :test?, fn -> false end)
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.License, :sign, fn ^hash -> "signature" end)
      stub(NaiveDateTime, :utc_now, fn :second -> date end)

      expect(Storage, :generate_download_url, fn ^object_key, _, _ ->
        download_url
      end)

      conn = Authentication.put_current_project(conn, project)

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
      assert Plug.Conn.get_resp_header(conn, "x-tuist-signature") == ["signature"]
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["url"] == download_url
      assert response_data["expires_at"]
    end

    test "errors if the account has no subscription and they've surpassed their limit", %{
      conn: conn,
      cache: cache
    } do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)

      Repo.update!(
        Ecto.Changeset.change(account,
          current_month_remote_cache_hits_count: Tuist.Billing.get_payment_thresholds()[:remote_cache_hits] * 2
        )
      )

      hash = "hash"
      name = "name"
      project_slug = "#{account.name}/#{project.name}"
      cache_category = "builds"

      conn = Authentication.put_current_project(conn, project)

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
      response = json_response(conn, 402)

      assert response["message"] == ~s"""
             The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
             """
    end

    test "returns download url with downcased full handle", %{conn: conn, cache: cache} do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "MyAccount", preload: [:account])

      project =
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
      date = ~N[2024-04-30 10:20:30Z]

      stub(NaiveDateTime, :utc_now, fn :second -> date end)

      expect(Storage, :generate_download_url, fn ^object_key, _, _ ->
        download_url
      end)

      conn = Authentication.put_current_project(conn, project)

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
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)
      stub(Tuist.License, :sign, fn ^hash -> "signature" end)

      CacheActionItems.create_cache_action_item(%{
        hash: hash,
        project: project
      })

      conn = Authentication.put_current_project(conn, project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> get(~p"/api/projects/#{account.name}/#{project.name}/cache/ac/hash")

      # Then
      response = json_response(conn, :ok)

      assert Plug.Conn.get_resp_header(conn, "x-tuist-signature") == ["signature"]

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
      {:ok, account} = Accounts.get_account_by_id(project.account_id)

      conn = Authentication.put_current_project(conn, project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> get(~p"/api/projects/#{account.name}/#{project.name}/cache/ac/hash")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{"message" => "The item doesn't exist in the cache."}
    end

    test "returns a payment required status code if the account has no subscription and their usage is above the threshold",
         %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"

      Repo.update!(
        Ecto.Changeset.change(account,
          current_month_remote_cache_hits_count: Tuist.Billing.get_payment_thresholds()[:remote_cache_hits] * 2
        )
      )

      CacheActionItems.create_cache_action_item(%{
        hash: hash,
        project: project
      })

      conn = Authentication.put_current_project(conn, project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> get(~p"/api/projects/#{account.name}/#{project.name}/cache/ac/hash")

      # Then
      response = json_response(conn, :payment_required)

      assert response == %{
               "message" => ~s"""
               The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
               """
             }
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/cache/:category" do
    test "creates a cache action item", %{conn: conn, cache: cache} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      project_id = project.id
      date = DateTime.utc_now(:second)
      stub(DateTime, :utc_now, fn :second -> date end)
      hash = UUIDv7.generate()

      conn = Authentication.put_current_user(conn, user)

      expect(Pipeline, :async_push, 1, fn {:create_cache_action_item,
                                           %{
                                             project_id: ^project_id,
                                             hash: ^hash,
                                             inserted_at: ^date,
                                             updated_at: ^date
                                           }} ->
        :ok
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:cache, cache)
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/cache/ac",
          %{
            hash: hash
          }
        )

      # Then
      response = json_response(conn, :created)

      assert response == %{
               "hash" => hash
             }
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

      conn = Authentication.put_current_user(conn, user)

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

    test "returns a payment_required method if the account doesn't have a subscription and has gone above the threshold",
         %{conn: conn, cache: cache} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      Repo.update!(
        Ecto.Changeset.change(account,
          current_month_remote_cache_hits_count: Tuist.Billing.get_payment_thresholds()[:remote_cache_hits] * 2
        )
      )

      project = ProjectsFixtures.project_fixture(account_id: account.id)
      date = DateTime.utc_now(:second)
      stub(DateTime, :utc_now, fn :second -> date end)
      hash = UUIDv7.generate()

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:cache, cache)
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/cache/ac",
          %{
            hash: hash
          }
        )

      # Then
      response = json_response(conn, :payment_required)

      assert response == %{
               "message" => ~s"""
               The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
               """
             }
    end
  end

  describe "POST /api/cache/multipart/start" do
    test "starts multipart upload", %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "12344"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      expect(Storage, :multipart_start, fn ^object_key, _actor ->
        upload_id
      end)

      conn = Authentication.put_current_project(conn, project)

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

    test "returns a payment_required error if the account has no subscription and they've gone above the threshold",
         %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"

      Repo.update!(
        Ecto.Changeset.change(account,
          current_month_remote_cache_hits_count: Tuist.Billing.get_payment_thresholds()[:remote_cache_hits] * 2
        )
      )

      conn = Authentication.put_current_project(conn, project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> post(
          ~p"/api/cache/multipart/start?hash=#{hash}&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}"
        )

      # # Then
      response = json_response(conn, :payment_required)

      assert response["message"] == ~s"""
             The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
             """
    end
  end

  describe "POST /api/cache/multipart/generate-url" do
    test "generates the url", %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"
      part_number = "3"
      upload_url = "https://tuist.dev/upload/1234"
      object_key = "#{project_id}/#{cache_category}/#{hash}/#{name}"

      expect(Storage, :multipart_generate_url, fn ^object_key,
                                                  ^upload_id,
                                                  ^part_number,
                                                  _actor,
                                                  [expires_in: _, content_length: 20] ->
        upload_url
      end)

      conn = Authentication.put_current_project(conn, project)

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

    test "errors with a payment_required if the account has no subscription and they've gone above the threshold",
         %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_id = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"
      part_number = "3"

      Repo.update!(
        Ecto.Changeset.change(account,
          current_month_remote_cache_hits_count: Tuist.Billing.get_payment_thresholds()[:remote_cache_hits] * 2
        )
      )

      conn = Authentication.put_current_project(conn, project)

      # When
      conn =
        conn
        |> assign(:cache, cache)
        |> post(
          ~p"/api/cache/multipart/generate-url?hash=#{hash}&content_length=20&name=#{name}&project_id=#{project_id}&cache_category=#{cache_category}&part_number=#{part_number}&upload_id=#{upload_id}"
        )

      # Then
      response = json_response(conn, :payment_required)

      assert response["message"] == ~s"""
             The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
             """
    end
  end

  describe "POST /api/cache/multipart/complete" do
    test "completes a multipart upload", %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_slug = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"
      object_key = "#{project_slug}/#{cache_category}/#{hash}/#{name}"
      date = ~N[2024-04-30 10:20:30Z]

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      stub(NaiveDateTime, :utc_now, fn :second -> date end)

      expect(Storage, :multipart_complete_upload, fn ^object_key,
                                                     ^upload_id,
                                                     [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}],
                                                     _actor ->
        :ok
      end)

      conn = Authentication.put_current_project(conn, project)

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
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
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

      stub(Storage, :multipart_complete_upload, fn _object_key, _upload_id, _parts, _actor ->
        :ok
      end)

      stub(Storage, :get_object_size, fn _, _ -> {:ok, 1024} end)
      conn = Authentication.put_current_project(conn, project)

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
    end

    test "succeeds even when object size cannot be retrieved (eventual consistency)", %{
      conn: conn,
      cache: cache
    } do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_slug = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"}
      ]

      stub(Storage, :multipart_complete_upload, fn _object_key, _upload_id, _parts, _actor ->
        :ok
      end)

      stub(Storage, :get_object_size, fn _, _ -> {:error, :not_found} end)
      conn = Authentication.put_current_project(conn, project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:cache, cache)
        |> assign(:skip_retry_sleep, true)
        |> post(
          ~p"/api/cache/multipart/complete?hash=#{hash}&name=#{name}&project_id=#{project_slug}&cache_category=#{cache_category}&upload_id=#{upload_id}",
          parts: parts
        )

      # Then
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"] == %{}
    end

    test "errors with a payment_required when the account has no subscription and has gone above the limit",
         %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      hash = "hash"
      name = "name"
      project_slug = "#{account.name}/#{project.name}"
      cache_category = "builds"
      upload_id = "1234"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      Repo.update!(
        Ecto.Changeset.change(account,
          current_month_remote_cache_hits_count: Tuist.Billing.get_payment_thresholds()[:remote_cache_hits] * 2
        )
      )

      conn = Authentication.put_current_project(conn, project)

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
      response = json_response(conn, :payment_required)

      assert response["message"] == ~s"""
             The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
             """
    end
  end

  describe "PUT /api/projects/:account_handle/:project_handle/cache/clean" do
    test "the given user project is cleaned", %{conn: conn, cache: cache} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        Oban.Testing.with_testing_mode(:manual, fn ->
          conn =
            conn
            |> Authentication.put_current_user(user)
            |> assign(:cache, cache)
            |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

          assert_enqueued(
            worker: CleanProjectWorker,
            args: %{project_id: project.id}
          )

          conn
        end)

      # Then
      response = response(conn, :no_content)
      assert response == ""
    end

    test "given organization project is cleaned", %{conn: conn, cache: cache} do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      user = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        Oban.Testing.with_testing_mode(:manual, fn ->
          conn =
            conn
            |> Authentication.put_current_user(user)
            |> assign(:cache, cache)
            |> put(~p"/api/projects/#{account.name}/#{project.name}/cache/clean")

          assert_enqueued(
            worker: CleanProjectWorker,
            args: %{project_id: project.id}
          )

          conn
        end)

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

      user = Repo.preload(AccountsFixtures.user_fixture(), :account)

      conn = Authentication.put_current_user(conn, user)

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

      conn = Authentication.put_current_user(conn, user)

      # When
      {_, _, payload} =
        assert_error_sent(:not_found, fn ->
          conn
          |> assign(:cache, cache)
          |> put(~p"/api/projects/#{account.name}/non-existing-project/cache/clean")
        end)

      # Then
      assert JSON.decode!(payload) ==
               %{"message" => "The project #{account.name}/non-existing-project was not found."}
    end
  end
end
