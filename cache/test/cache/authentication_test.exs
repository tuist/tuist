defmodule Cache.AuthenticationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Authentication
  import Cache.Authentication

  @cache_name :cas_auth_cache
  @test_auth_header "Bearer test-token-123"
  @test_server_url "http://localhost:4000"

  setup do
    Cachex.clear(@cache_name)

    Authentication
    |> stub(:server_url, fn -> @test_server_url end)

    :ok
  end

  describe "ensure_project_accessible/3" do
    test "returns error when authorization header is missing" do
      conn = build_conn([])

      result = Authentication.ensure_project_accessible(conn, "account", "project")

      assert result == {:error, 401, "Missing Authorization header"}
    end

    test "returns ok with auth header when project is accessible" do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project")

      assert {:ok, @test_auth_header} = result
    end

    test "handles case-insensitive project handles" do
      projects = [%{"full_name" => "Account/Project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "ACCOUNT", "PROJECT")

      assert {:ok, @test_auth_header} = result
    end

    test "returns error when project is not in accessible list" do
      projects = [%{"full_name" => "other-account/other-project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project")

      assert result == {:error, 404, "Unauthorized or not found"}
    end

    test "returns error when server returns 401" do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(401, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project")

      assert result == {:error, 401, "Unauthorized"}
    end

    test "returns error when server returns 403" do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(403, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project")

      assert result == {:error, 404, "Unauthorized or not found"}
    end

    test "handles other server error status codes" do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(500, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project")

      assert result == {:error, 500, "Server responded with status 500"}
    end

    test "forwards x-request-id header to server" do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}, {"x-request-id", "req-123"}])

      stub_api_call_with_headers(
        200,
        %{"projects" => projects},
        [{"authorization", @test_auth_header}, {"x-request-id", "req-123"}]
      )

      result = Authentication.ensure_project_accessible(conn, "account", "project")

      assert {:ok, @test_auth_header} = result
    end
  end

  describe "caching behavior" do
    test "caches successful authorization responses" do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      Authentication.ensure_project_accessible(conn, "account", "project")

      cache_key = {generate_cache_key(@test_auth_header), "account/project"}

      {:ok, :ok} = Cachex.get(@cache_name, cache_key)
    end

    test "uses cached result on subsequent calls" do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      Req.Test.expect(Cache.Authentication, fn conn ->
        Req.Test.json(conn, %{"projects" => projects})
      end)

      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project")
      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project")
    end

    test "caches 401 errors with shorter TTL" do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(401, nil)

      Authentication.ensure_project_accessible(conn, "account", "project")

      cache_key = {generate_cache_key(@test_auth_header), "account/project"}
      {:ok, cached_result} = Cachex.get(@cache_name, cache_key)

      assert cached_result == {:error, 401, "Unauthorized"}
    end

    test "caches 403 errors with shorter TTL" do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(403, nil)

      Authentication.ensure_project_accessible(conn, "account", "project")

      cache_key = {generate_cache_key(@test_auth_header), "account/project"}
      {:ok, cached_result} = Cachex.get(@cache_name, cache_key)

      assert cached_result == {:error, 404, "Unauthorized or not found"}
    end

    test "different auth headers have different cache keys" do
      other_auth_header = "Bearer other-token-456"
      projects1 = [%{"full_name" => "account1/project1"}]
      projects2 = [%{"full_name" => "account2/project2"}]

      conn1 = build_conn([{"authorization", @test_auth_header}])
      conn2 = build_conn([{"authorization", other_auth_header}])

      stub_api_call(200, %{"projects" => projects1})
      {:ok, _} = Authentication.ensure_project_accessible(conn1, "account1", "project1")

      stub_api_call(200, %{"projects" => projects2})
      {:ok, _} = Authentication.ensure_project_accessible(conn2, "account2", "project2")

      cache_key1 = {generate_cache_key(@test_auth_header), "account1/project1"}
      cache_key2 = {generate_cache_key(other_auth_header), "account2/project2"}

      {:ok, :ok} = Cachex.get(@cache_name, cache_key1)
      {:ok, :ok} = Cachex.get(@cache_name, cache_key2)

      refute cache_key1 == cache_key2
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec for supervision tree" do
      spec = Authentication.child_spec([])

      assert %{id: Cache.Authentication, start: {Cachex, :start_link, [@cache_name, []]}} = spec
    end
  end

  defp build_conn(headers) do
    %Plug.Conn{
      req_headers: headers,
      adapter: {Plug.Adapters.Test.Conn, :...}
    }
  end

  defp stub_api_call(status, body) do
    stub_api_call_with_headers(status, body, nil)
  end

  defp stub_api_call_with_headers(status, body, expected_headers) do
    Req.Test.stub(Cache.Authentication, fn conn ->
      if expected_headers do
        for {key, value} <- expected_headers do
          assert value in Plug.Conn.get_req_header(conn, key)
        end
      end

      if body do
        Req.Test.json(conn, body)
      else
        Plug.Conn.send_resp(conn, status, "")
      end
    end)
  end
end
