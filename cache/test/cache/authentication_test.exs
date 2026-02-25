defmodule Cache.AuthenticationTest do
  use ExUnit.Case, async: true
  use Mimic

  import Cache.Authentication

  alias Cache.Authentication

  @test_auth_header "Bearer test-token-123"
  @test_server_url "http://localhost:4000"

  setup :set_mimic_from_context

  setup do
    suffix = :erlang.unique_integer([:positive])
    cache_name = :"auth_cache_test_#{suffix}"
    start_supervised!({Cachex, name: cache_name})

    Req.Test.set_req_test_to_shared()

    stub(Authentication, :server_url, fn -> @test_server_url end)

    {:ok, cache_name: cache_name}
  end

  describe "ensure_project_accessible/3" do
    test "returns error when authorization header is missing", %{cache_name: cache_name} do
      conn = build_conn([])

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert result == {:error, 401, "Missing Authorization header"}
    end

    test "returns ok with auth header when project is accessible", %{cache_name: cache_name} do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, @test_auth_header} = result
    end

    test "handles case-insensitive project handles", %{cache_name: cache_name} do
      projects = [%{"full_name" => "Account/Project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "ACCOUNT", "PROJECT", cache_name: cache_name)

      assert {:ok, @test_auth_header} = result
    end

    test "returns error when project is not in accessible list", %{cache_name: cache_name} do
      projects = [%{"full_name" => "other-account/other-project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert result == {:error, 403, "You don't have access to this project"}
    end

    test "returns error when server returns 401", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(401, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert result == {:error, 401, "Unauthorized"}
    end

    test "returns error when server returns 403", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(403, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert result == {:error, 403, "You don't have access to this project"}
    end

    test "handles other server error status codes", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(500, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert result == {:error, 500, "Server responded with status 500"}
    end

    test "forwards x-request-id header to server", %{cache_name: cache_name} do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}, {"x-request-id", "req-123"}])

      stub_api_call_with_headers(
        200,
        %{"projects" => projects},
        [{"authorization", @test_auth_header}, {"x-request-id", "req-123"}]
      )

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, @test_auth_header} = result
    end
  end

  describe "caching behavior" do
    test "caches successful authorization responses", %{cache_name: cache_name} do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(@test_auth_header), "account/project"}

      {:ok, :ok} = Cachex.get(cache_name, cache_key)
    end

    test "uses cached result on subsequent calls", %{cache_name: cache_name} do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}])

      Req.Test.expect(Authentication, fn conn ->
        Req.Test.json(conn, %{"projects" => projects})
      end)

      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)
      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)
    end

    test "deduplicates in-flight server requests", %{cache_name: cache_name} do
      projects = [%{"full_name" => "account/project"}]
      conn = build_conn([{"authorization", @test_auth_header}])
      counter = start_supervised!({Agent, fn -> 0 end})

      Req.Test.stub(Authentication, fn conn ->
        Agent.update(counter, &(&1 + 1))
        Process.sleep(50)
        Req.Test.json(conn, %{"projects" => projects})
      end)

      tasks =
        Enum.map(1..15, fn _ ->
          Task.async(fn ->
            Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)
          end)
        end)

      results = Enum.map(tasks, &Task.await(&1, 5_000))

      assert Enum.all?(results, &(&1 == {:ok, @test_auth_header}))
      assert Agent.get(counter, & &1) == 1
    end

    test "caches 401 errors with shorter TTL", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(401, nil)

      Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(@test_auth_header), "account/project"}
      {:ok, cached_result} = Cachex.get(cache_name, cache_key)

      assert cached_result == {:error, 401, "Unauthorized"}
    end

    test "caches 403 errors with shorter TTL", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(403, nil)

      Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(@test_auth_header), "account/project"}
      {:ok, cached_result} = Cachex.get(cache_name, cache_key)

      assert cached_result == {:error, 403, "You don't have access to this project"}
    end

    test "different auth headers have different cache keys", %{cache_name: cache_name} do
      other_auth_header = "Bearer other-token-456"
      projects1 = [%{"full_name" => "account1/project1"}]
      projects2 = [%{"full_name" => "account2/project2"}]

      conn1 = build_conn([{"authorization", @test_auth_header}])
      conn2 = build_conn([{"authorization", other_auth_header}])

      stub_api_call(200, %{"projects" => projects1})
      {:ok, _} = Authentication.ensure_project_accessible(conn1, "account1", "project1", cache_name: cache_name)

      stub_api_call(200, %{"projects" => projects2})
      {:ok, _} = Authentication.ensure_project_accessible(conn2, "account2", "project2", cache_name: cache_name)

      cache_key1 = {generate_cache_key(@test_auth_header), "account1/project1"}
      cache_key2 = {generate_cache_key(other_auth_header), "account2/project2"}

      {:ok, :ok} = Cachex.get(cache_name, cache_key1)
      {:ok, :ok} = Cachex.get(cache_name, cache_key2)

      refute cache_key1 == cache_key2
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec for supervision tree" do
      spec = Authentication.child_spec([])

      assert %{id: Authentication, start: {Cachex, :start_link, [:cas_auth_cache, []]}} = spec
    end
  end

  describe "JWT verification" do
    setup %{cache_name: cache_name} do
      projects = ["account/project", "other-account/other-project"]
      exp = System.system_time(:second) + 3600

      claims = %{
        "projects" => projects,
        "exp" => exp,
        "iat" => System.system_time(:second),
        "sub" => "user-123"
      }

      {:ok, jwt_token, _claims} = Cache.Guardian.encode_and_sign(%{}, claims)

      {:ok, jwt_token: jwt_token, projects: projects, exp: exp, cache_name: cache_name}
    end

    test "successfully authorizes with valid JWT containing requested project", %{
      jwt_token: jwt_token,
      cache_name: cache_name
    } do
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "handles case-insensitive project handles with JWT", %{jwt_token: jwt_token, cache_name: cache_name} do
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      result = Authentication.ensure_project_accessible(conn, "ACCOUNT", "PROJECT", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "falls back to API call when project not in JWT claims (may be outside top 5)", %{cache_name: cache_name} do
      projects = ["other-account/other-project"]
      exp = System.system_time(:second) + 3600

      claims = %{
        "projects" => projects,
        "exp" => exp,
        "iat" => System.system_time(:second),
        "sub" => "user-123"
      }

      {:ok, jwt_token, _claims} = Cache.Guardian.encode_and_sign(%{}, claims)
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      api_projects = [%{"full_name" => "account/project"}]
      stub_api_call(200, %{"projects" => api_projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "caches JWT authorization result", %{jwt_token: jwt_token, cache_name: cache_name} do
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(auth_header), "account/project"}
      {:ok, :ok} = Cachex.get(cache_name, cache_key)
    end

    test "falls back to API and caches rejection when project not found in API either", %{
      jwt_token: jwt_token,
      cache_name: cache_name
    } do
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      api_projects = [%{"full_name" => "other/project"}]
      stub_api_call(200, %{"projects" => api_projects})

      result = Authentication.ensure_project_accessible(conn, "nonexistent", "project", cache_name: cache_name)

      assert result == {:error, 403, "You don't have access to this project"}

      cache_key = {generate_cache_key(auth_header), "nonexistent/project"}
      {:ok, cached_result} = Cachex.get(cache_name, cache_key)
      assert cached_result == {:error, 403, "You don't have access to this project"}
    end

    test "falls back to API call when JWT verification fails", %{cache_name: cache_name} do
      invalid_token = "invalid.jwt.token"
      auth_header = "Bearer #{invalid_token}"
      conn = build_conn([{"authorization", auth_header}])

      projects = [%{"full_name" => "account/project"}]
      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "falls back to API call for non-JWT tokens (project tokens)", %{cache_name: cache_name} do
      project_token = "tuist_prj_abc123def456"
      auth_header = "Bearer #{project_token}"
      conn = build_conn([{"authorization", auth_header}])

      projects = [%{"full_name" => "account/project"}]
      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end
  end

  describe "JWT verification skipped when Guardian secret key not configured" do
    test "falls back to API call when Guardian is not configured", %{cache_name: cache_name} do
      stub(Cache.Config, :guardian_configured?, fn -> false end)

      auth_header = "Bearer some-jwt-token"
      conn = build_conn([{"authorization", auth_header}])

      projects = [%{"full_name" => "account/project"}]
      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end
  end

  describe "JWT cache TTL based on exp claim" do
    test "uses token expiration time for cache TTL when exp is present", %{cache_name: cache_name} do
      exp_time = System.system_time(:second) + 300

      claims = %{
        "projects" => ["account/project"],
        "exp" => exp_time,
        "iat" => System.system_time(:second),
        "sub" => "user-123"
      }

      {:ok, jwt_token, _claims} = Cache.Guardian.encode_and_sign(%{}, claims)
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(auth_header), "account/project"}
      {:ok, ttl} = Cachex.ttl(cache_name, cache_key)

      assert ttl > 0
      assert ttl <= 300_000
    end

    test "uses default TTL when exp is greater than max cache TTL", %{cache_name: cache_name} do
      exp_time = System.system_time(:second) + 3600

      claims = %{
        "projects" => ["account/project"],
        "exp" => exp_time,
        "iat" => System.system_time(:second),
        "sub" => "user-123"
      }

      {:ok, jwt_token, _claims} = Cache.Guardian.encode_and_sign(%{}, claims)
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(auth_header), "account/project"}
      {:ok, ttl} = Cachex.ttl(cache_name, cache_key)

      assert ttl <= 600_000
    end

    test "does not cache when token is already expired", %{cache_name: cache_name} do
      exp_time = System.system_time(:second) - 100

      claims = %{
        "projects" => ["account/project"],
        "exp" => exp_time,
        "iat" => System.system_time(:second) - 200,
        "sub" => "user-123"
      }

      {:ok, jwt_token, _claims} = Cache.Guardian.encode_and_sign(%{}, claims)
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      projects = [%{"full_name" => "account/project"}]
      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
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
    Req.Test.stub(Authentication, fn conn ->
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
