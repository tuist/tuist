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
      projects = ["account/project"]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, @test_auth_header} = result
    end

    # Cache access resolution comes from the server's cache-scoped endpoint,
    # which already drops accounts that have exhausted the free tier.
    test "resolves access from the cache access endpoint", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"accounts" => [], "projects" => ["account/project"]})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, @test_auth_header} = result
    end

    test "denies a project the cache access endpoint leaves out", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"accounts" => [], "projects" => []})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _} = result
    end

    # `projects` names what the credential reaches, not what it may do there:
    # a read-only token or a viewer is listed too. The grants beside it carry
    # the action, so they decide.
    test "a project the access endpoint grants only reads to is not writable", %{cache_name: cache_name} do
      stub_api_call(200, %{
        "projects" => ["account/project"],
        "cache_grants" => %{"project" => %{"read" => ["account/project"], "write" => []}}
      })

      assert {:ok, @test_auth_header} =
               Authentication.ensure_project_accessible(
                 build_conn([{"authorization", @test_auth_header}], "GET"),
                 "account",
                 "project",
                 cache_name: cache_name
               )

      for method <- ["PUT", "POST", "DELETE"] do
        assert {:error, 403, _message} =
                 Authentication.ensure_project_accessible(
                   build_conn([{"authorization", @test_auth_header}], method),
                   "account",
                   "project",
                   cache_name: cache_name
                 )
      end
    end

    test "a project the access endpoint grants writes to is readable and writable", %{cache_name: cache_name} do
      stub_api_call(200, %{
        "projects" => ["account/project"],
        "cache_grants" => %{"project" => %{"read" => [], "write" => ["account/project"]}}
      })

      for method <- ["GET", "PUT", "DELETE"] do
        assert {:ok, @test_auth_header} =
                 Authentication.ensure_project_accessible(
                   build_conn([{"authorization", @test_auth_header}], method),
                   "account",
                   "project",
                   cache_name: cache_name
                 )
      end
    end

    test "a project the access endpoint lists but grants nothing on is denied", %{cache_name: cache_name} do
      stub_api_call(200, %{
        "projects" => ["account/project"],
        "cache_grants" => %{"project" => %{"read" => [], "write" => []}}
      })

      assert {:error, 403, _message} =
               Authentication.ensure_project_accessible(
                 build_conn([{"authorization", @test_auth_header}], "GET"),
                 "account",
                 "project",
                 cache_name: cache_name
               )
    end

    # A read-only credential uploads for its whole build. Its refused writes are
    # held as long as an allowed answer, or each would ask the server again.
    test "holds a write refused on a readable project as long as an allowed answer", %{cache_name: cache_name} do
      stub_api_call(200, %{
        "projects" => ["account/project"],
        "cache_grants" => %{"project" => %{"read" => ["account/project"], "write" => []}}
      })

      for method <- ["GET", "PUT"] do
        Authentication.ensure_project_accessible(
          build_conn([{"authorization", @test_auth_header}], method),
          "account",
          "project",
          cache_name: cache_name
        )
      end

      key = generate_cache_key(@test_auth_header)
      {:ok, read_ttl} = Cachex.ttl(cache_name, {key, "account/project", :read})
      {:ok, write_ttl} = Cachex.ttl(cache_name, {key, "account/project", :write})

      assert {:ok, {:error, 403, _}} = Cachex.get(cache_name, {key, "account/project", :write})
      # Server answers expire: an entry without a TTL outlives a revocation.
      assert is_integer(read_ttl) and read_ttl <= to_timeout(second: 600)
      assert is_integer(write_ttl) and write_ttl > to_timeout(minute: 1)
      assert_in_delta write_ttl, read_ttl, to_timeout(second: 5)
    end

    test "keeps a refusal for a project the credential cannot read short-lived", %{cache_name: cache_name} do
      stub_api_call(200, %{
        "projects" => [],
        "cache_grants" => %{"project" => %{"read" => [], "write" => []}}
      })

      Authentication.ensure_project_accessible(
        build_conn([{"authorization", @test_auth_header}], "PUT"),
        "account",
        "project",
        cache_name: cache_name
      )

      {:ok, ttl} =
        Cachex.ttl(cache_name, {generate_cache_key(@test_auth_header), "account/project", :write})

      assert is_integer(ttl) and ttl <= to_timeout(second: 3)
    end

    test "answers payment required when the grants leave the project out for billing", %{cache_name: cache_name} do
      stub_api_call(200, %{
        "projects" => [],
        "cache_grants" => %{"project" => %{"read" => [], "write" => []}},
        "payment_required" => ["account"]
      })

      for method <- ["GET", "PUT"] do
        assert {:error, 402, message} =
                 Authentication.ensure_project_accessible(
                   build_conn([{"authorization", @test_auth_header}], method),
                   "account",
                   "project",
                   cache_name: cache_name
                 )

        assert message =~ "Tuist Air"
      end
    end

    test "authorizes from grants alone, comparing handles case-insensitively", %{cache_name: cache_name} do
      stub_api_call(200, %{
        "cache_grants" => %{"project" => %{"read" => [], "write" => ["Account/Project"]}}
      })

      for method <- ["GET", "PUT"] do
        assert {:ok, @test_auth_header} =
                 Authentication.ensure_project_accessible(
                   build_conn([{"authorization", @test_auth_header}], method),
                   "account",
                   "project",
                   cache_name: cache_name
                 )
      end
    end

    # Absence from the grants is how an exhausted plan reaches a cache node, and
    # on its own it is indistinguishable from never having had access. Answering
    # 403 sends the caller looking for a permissions problem they do not have.
    test "answers payment required when the access endpoint names the account", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"accounts" => [], "projects" => [], "payment_required" => ["account"]})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 402, message} = result
      assert message =~ "Tuist Air"
    end

    test "still answers forbidden when the account is simply out of reach", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"accounts" => [], "projects" => [], "payment_required" => []})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _} = result
    end

    test "handles case-insensitive project handles", %{cache_name: cache_name} do
      projects = ["Account/Project"]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "ACCOUNT", "PROJECT", cache_name: cache_name)

      assert {:ok, @test_auth_header} = result
    end

    test "returns error when project is not in accessible list", %{cache_name: cache_name} do
      projects = ["other-account/other-project"]
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

    test "answers unavailable when the server fails and nothing was confirmed", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(500, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert result == {:error, 503, "Authentication backend unavailable"}
    end

    test "passes through other server statuses without caching them", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(404, nil)

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert result == {:error, 404, "Server responded with status 404"}
      assert {:ok, nil} = Cachex.get(cache_name, {generate_cache_key(@test_auth_header), "account/project", :read})
    end

    test "does not forward a request id that does not look like one", %{cache_name: cache_name} do
      for {request_id, forwarded?} <- [
            {"req-123:abc.def_0", true},
            {"bad id\twith spaces", false},
            {String.duplicate("a", 201), false}
          ] do
        auth_header = "Bearer token-#{:erlang.unique_integer([:positive])}"
        test_pid = self()

        Req.Test.stub(Authentication, fn conn ->
          send(test_pid, {:request_id, Plug.Conn.get_req_header(conn, "x-request-id")})
          Req.Test.json(conn, %{"projects" => ["account/project"]})
        end)

        conn = build_conn([{"authorization", auth_header}, {"x-request-id", request_id}])
        {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

        expected = if forwarded?, do: [request_id], else: []
        assert_receive {:request_id, ^expected}
      end
    end

    test "forwards x-request-id header to server", %{cache_name: cache_name} do
      projects = ["account/project"]
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
      projects = ["account/project"]
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(200, %{"projects" => projects})

      Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(@test_auth_header), "account/project", :read}

      {:ok, :ok} = Cachex.get(cache_name, cache_key)
    end

    test "uses cached result on subsequent calls", %{cache_name: cache_name} do
      projects = ["account/project"]
      conn = build_conn([{"authorization", @test_auth_header}])

      Req.Test.expect(Authentication, fn conn ->
        Req.Test.json(conn, %{"projects" => projects})
      end)

      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)
      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)
    end

    test "deduplicates in-flight server requests", %{cache_name: cache_name} do
      projects = ["account/project"]
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

      cache_key = {generate_cache_key(@test_auth_header), "account/project", :read}
      {:ok, cached_result} = Cachex.get(cache_name, cache_key)

      assert cached_result == {:error, 401, "Unauthorized"}
    end

    test "caches 403 errors with shorter TTL", %{cache_name: cache_name} do
      conn = build_conn([{"authorization", @test_auth_header}])

      stub_api_call(403, nil)

      Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(@test_auth_header), "account/project", :read}
      {:ok, cached_result} = Cachex.get(cache_name, cache_key)

      assert cached_result == {:error, 403, "You don't have access to this project"}
    end

    test "different auth headers have different cache keys", %{cache_name: cache_name} do
      other_auth_header = "Bearer other-token-456"
      projects1 = ["account1/project1"]
      projects2 = ["account2/project2"]

      conn1 = build_conn([{"authorization", @test_auth_header}])
      conn2 = build_conn([{"authorization", other_auth_header}])

      stub_api_call(200, %{"projects" => projects1})
      {:ok, _} = Authentication.ensure_project_accessible(conn1, "account1", "project1", cache_name: cache_name)

      stub_api_call(200, %{"projects" => projects2})
      {:ok, _} = Authentication.ensure_project_accessible(conn2, "account2", "project2", cache_name: cache_name)

      cache_key1 = {generate_cache_key(@test_auth_header), "account1/project1", :read}
      cache_key2 = {generate_cache_key(other_auth_header), "account2/project2", :read}

      {:ok, :ok} = Cachex.get(cache_name, cache_key1)
      {:ok, :ok} = Cachex.get(cache_name, cache_key2)

      refute cache_key1 == cache_key2
    end
  end

  # While the server cannot answer, a settled answer it confirmed in the last
  # 25 minutes is still served, so an outage does not fail every build. The
  # entries are deleted below to stand in for their 600 s freshness running out.
  describe "server outage" do
    setup do
      key = generate_cache_key(@test_auth_header)
      {:ok, key: key, read: {key, "account/project", :read}, write: {key, "account/project", :write}}
    end

    test "serves a confirmed answer while the server fails", %{cache_name: cache_name, read: read} do
      confirm(cache_name, "GET", %{"projects" => ["account/project"]})

      for failure <- [503, 500, 502, 504, :econnrefused, :timeout, :html] do
        Cachex.del(cache_name, read)
        respond_with(failure)

        assert {:ok, @test_auth_header} = request(cache_name, "GET"), "expected a stale answer on #{inspect(failure)}"
      end
    end

    test "keeps the confirmed answer for 25 minutes from the confirmation, without extending it", %{
      cache_name: cache_name,
      read: read
    } do
      confirm(cache_name, "GET", %{"projects" => ["account/project"]})

      {:ok, confirmed_ttl} = Cachex.ttl(cache_name, {:confirmed, read})
      assert confirmed_ttl > to_timeout(second: 600) and confirmed_ttl <= to_timeout(second: 1500)

      Cachex.del(cache_name, read)
      respond_with(503)
      {:ok, _} = request(cache_name, "GET")

      {:ok, stale_ttl} = Cachex.ttl(cache_name, read)
      {:ok, confirmed_ttl_after} = Cachex.ttl(cache_name, {:confirmed, read})
      assert stale_ttl <= to_timeout(second: 3)
      assert confirmed_ttl_after <= confirmed_ttl
    end

    test "stops serving it once its window is over", %{cache_name: cache_name, read: read} do
      confirm(cache_name, "GET", %{"projects" => ["account/project"]})
      Cachex.expire(cache_name, {:confirmed, read}, 1)
      Process.sleep(10)
      Cachex.del(cache_name, read)
      respond_with(503)

      assert {:error, 503, _} = request(cache_name, "GET")
    end

    test "a refusal after the confirmation is not undone by an outage", %{cache_name: cache_name, read: read} do
      confirm(cache_name, "GET", %{"projects" => ["account/project"]})
      Cachex.del(cache_name, read)
      confirm(cache_name, "GET", %{"projects" => []})
      Cachex.del(cache_name, read)
      respond_with(503)

      assert {:error, 503, _} = request(cache_name, "GET")
    end

    test "a 401 on one action voids the credential's confirmed answers for every action", %{
      cache_name: cache_name,
      read: read,
      write: write
    } do
      body = %{
        "projects" => ["account/project"],
        "cache_grants" => %{"project" => %{"read" => [], "write" => ["account/project"]}}
      }

      confirm(cache_name, "GET", body)
      confirm(cache_name, "PUT", body)

      Cachex.del(cache_name, write)
      respond_with(401)
      assert {:error, 401, _} = request(cache_name, "PUT")

      Cachex.del(cache_name, read)
      respond_with(503)
      assert {:error, 503, _} = request(cache_name, "GET")
    end

    test "a 401 for a token never confirmed leaves nothing long-lived", %{cache_name: cache_name, key: key} do
      respond_with(401)
      assert {:error, 401, _} = request(cache_name, "GET")

      assert {:ok, nil} = Cachex.get(cache_name, {:credential, key})
    end

    test "short refusals are not served stale, so a new grant is not hidden", %{cache_name: cache_name, read: read} do
      for body <- [%{"projects" => []}, %{"projects" => [], "payment_required" => ["account"]}] do
        confirm(cache_name, "GET", body)
        Cachex.del(cache_name, read)
        respond_with(503)

        assert {:error, 503, _} = request(cache_name, "GET")
        Cachex.del(cache_name, read)
      end
    end

    # Answering it 503 instead would make Gradle drop the remote cache for the
    # build, loads included; 403 only tells it to stop pushing.
    test "a write refused on a readable project stays refused during an outage", %{
      cache_name: cache_name,
      write: write
    } do
      confirm(cache_name, "PUT", %{
        "projects" => ["account/project"],
        "cache_grants" => %{"project" => %{"read" => ["account/project"], "write" => []}}
      })

      Cachex.del(cache_name, write)
      respond_with(503)

      assert {:error, 403, _} = request(cache_name, "PUT")
    end

    test "holds a stale answer briefly instead of asking a failing server on every request", %{
      cache_name: cache_name,
      read: read
    } do
      confirm(cache_name, "GET", %{"projects" => ["account/project"]})
      Cachex.del(cache_name, read)
      counter = count_and_respond(503)

      assert {:ok, _} = request(cache_name, "GET")
      assert {:ok, _} = request(cache_name, "GET")
      assert Agent.get(counter, & &1) == 1

      {:ok, ttl} = Cachex.ttl(cache_name, read)
      assert ttl <= to_timeout(second: 3)
    end

    # Clients retry a 503 within a few seconds; remembering it would fail
    # those retries after the server is back.
    test "does not remember an unavailable answer when nothing was confirmed", %{
      cache_name: cache_name,
      read: read
    } do
      counter = count_and_respond(503)

      assert {:error, 503, _} = request(cache_name, "GET")
      assert {:error, 503, _} = request(cache_name, "GET")
      assert Agent.get(counter, & &1) == 2
      assert {:ok, nil} = Cachex.get(cache_name, read)

      stub_api_call(200, %{"projects" => ["account/project"]})
      assert {:ok, _} = request(cache_name, "GET")
    end

    test "treats a request that raises as an outage", %{cache_name: cache_name, read: read} do
      confirm(cache_name, "GET", %{"projects" => ["account/project"]})
      Cachex.del(cache_name, read)

      Req.Test.stub(Authentication, fn _conn ->
        raise "Finch was unable to provide a connection within the timeout"
      end)

      assert {:ok, @test_auth_header} = request(cache_name, "GET")
    end

    test "a refused read also forgets the confirmed write", %{cache_name: cache_name, read: read, write: write} do
      body = %{
        "projects" => ["account/project"],
        "cache_grants" => %{"project" => %{"read" => [], "write" => ["account/project"]}}
      }

      confirm(cache_name, "GET", body)
      confirm(cache_name, "PUT", body)

      Cachex.del(cache_name, read)
      confirm(cache_name, "GET", %{"projects" => [], "cache_grants" => %{"project" => %{"read" => [], "write" => []}}})

      Cachex.del(cache_name, write)
      respond_with(503)
      assert {:error, 503, _} = request(cache_name, "PUT")
    end

    # An answer the server sent before the credential was revoked can arrive
    # after a 401 on another key; it must not make the credential valid again.
    test "a late confirmation does not undo a 401", %{cache_name: cache_name, read: read} do
      confirm(cache_name, "GET", %{"projects" => ["account/project", "account/other"]})

      respond_with(401)
      assert {:error, 401, _} = request(cache_name, "PUT", "other")

      stub_api_call(200, %{"projects" => ["account/project", "account/other"]})
      assert {:ok, _} = request(cache_name, "GET", "other")

      Cachex.del(cache_name, read)
      respond_with(503)
      assert {:error, 503, _} = request(cache_name, "GET")
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

      api_projects = ["account/project"]
      stub_api_call(200, %{"projects" => api_projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "caches JWT authorization result", %{jwt_token: jwt_token, cache_name: cache_name} do
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      {:ok, _} = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      cache_key = {generate_cache_key(auth_header), "account/project", :read}
      {:ok, :ok} = Cachex.get(cache_name, cache_key)
    end

    test "falls back to API and caches rejection when project not found in API either", %{
      jwt_token: jwt_token,
      cache_name: cache_name
    } do
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}])

      api_projects = ["other/project"]
      stub_api_call(200, %{"projects" => api_projects})

      result = Authentication.ensure_project_accessible(conn, "nonexistent", "project", cache_name: cache_name)

      assert result == {:error, 403, "You don't have access to this project"}

      cache_key = {generate_cache_key(auth_header), "nonexistent/project", :read}
      {:ok, cached_result} = Cachex.get(cache_name, cache_key)
      assert cached_result == {:error, 403, "You don't have access to this project"}
    end

    test "falls back to API call when JWT verification fails", %{cache_name: cache_name} do
      invalid_token = "invalid.jwt.token"
      auth_header = "Bearer #{invalid_token}"
      conn = build_conn([{"authorization", auth_header}])

      projects = ["account/project"]
      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "falls back to API call for non-JWT tokens (project tokens)", %{cache_name: cache_name} do
      project_token = "tuist_prj_abc123def456"
      auth_header = "Bearer #{project_token}"
      conn = build_conn([{"authorization", auth_header}])

      projects = ["account/project"]
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

      projects = ["account/project"]
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

      cache_key = {generate_cache_key(auth_header), "account/project", :read}
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

      cache_key = {generate_cache_key(auth_header), "account/project", :read}
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

      projects = ["account/project"]
      stub_api_call(200, %{"projects" => projects})

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end
  end

  describe "cache grants" do
    setup %{cache_name: cache_name} do
      {:ok, cache_name: cache_name}
    end

    test "authorizes a read the project bucket grants", %{cache_name: cache_name} do
      auth_header = grants_auth_header(read: ["account/project"])
      conn = build_conn([{"authorization", auth_header}], "GET")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "authorizes a write the project bucket grants", %{cache_name: cache_name} do
      auth_header = grants_auth_header(write: ["account/project"])
      conn = build_conn([{"authorization", auth_header}], "PUT")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "a write grant carries the read it implies", %{cache_name: cache_name} do
      auth_header = grants_auth_header(write: ["account/project"])
      conn = build_conn([{"authorization", auth_header}], "GET")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "compares handles case-insensitively", %{cache_name: cache_name} do
      auth_header = grants_auth_header(write: ["Account/Project"])
      conn = build_conn([{"authorization", auth_header}], "PUT")

      result = Authentication.ensure_project_accessible(conn, "ACCOUNT", "PROJECT", cache_name: cache_name)

      assert {:ok, ^auth_header} = result
    end

    test "denies a write a read grant does not cover, without asking the server", %{cache_name: cache_name} do
      Req.Test.stub(Authentication, fn _conn ->
        flunk("a token carrying grants has already had its say")
      end)

      auth_header = grants_auth_header(read: ["account/project"])
      conn = build_conn([{"authorization", auth_header}], "PUT")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _message} = result
    end

    test "denies a project the grants do not name", %{cache_name: cache_name} do
      auth_header = grants_auth_header(read: ["account/other-project"], write: ["account/other-project"])
      conn = build_conn([{"authorization", auth_header}], "GET")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _message} = result
    end

    test "an authorized read does not authorize a write", %{cache_name: cache_name} do
      auth_header = grants_auth_header(read: ["account/project"])

      assert {:ok, ^auth_header} =
               Authentication.ensure_project_accessible(
                 build_conn([{"authorization", auth_header}], "GET"),
                 "account",
                 "project",
                 cache_name: cache_name
               )

      assert {:error, 403, _message} =
               Authentication.ensure_project_accessible(
                 build_conn([{"authorization", auth_header}], "PUT"),
                 "account",
                 "project",
                 cache_name: cache_name
               )
    end

    test "denies a project a cache token's grants do not name, without asking the server", %{cache_name: cache_name} do
      Req.Test.stub(Authentication, fn _conn ->
        flunk("a cache token's grants are complete")
      end)

      auth_header = grants_auth_header(write: ["account/other-project"])
      conn = build_conn([{"authorization", auth_header}], "GET")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _message} = result
    end

    test "asks the server about a project an access token's grants leave out", %{cache_name: cache_name} do
      stub_api_call(200, %{"projects" => ["account/project"]})

      auth_header = grants_auth_header(write: ["account/other-project"], typ: "access")

      for method <- ["GET", "PUT"] do
        conn = build_conn([{"authorization", auth_header}], method)

        assert {:ok, ^auth_header} =
                 Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)
      end
    end

    test "denies a project neither an access token's grants nor the server name", %{cache_name: cache_name} do
      stub_api_call(200, %{"projects" => ["account/other-project"]})

      auth_header = grants_auth_header(write: ["account/other-project"], typ: "access")
      conn = build_conn([{"authorization", auth_header}], "GET")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _message} = result
    end

    test "denies a write on a project an access token grants only reads to, without asking the server", %{
      cache_name: cache_name
    } do
      Req.Test.stub(Authentication, fn _conn ->
        flunk("the grants name this project, so they are the answer")
      end)

      auth_header = grants_auth_header(read: ["account/project"], typ: "access")
      conn = build_conn([{"authorization", auth_header}], "PUT")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _message} = result
    end

    test "an account grant is not access to the projects in it", %{cache_name: cache_name} do
      claims = %{
        "cache_grants" => %{
          "account" => %{"read" => ["account"], "write" => ["account"]},
          "project" => %{"read" => [], "write" => []}
        },
        "exp" => System.system_time(:second) + 3600,
        "iat" => System.system_time(:second),
        "sub" => "user-123",
        "typ" => "cache"
      }

      {:ok, jwt_token, _claims} = Cache.Guardian.encode_and_sign(%{}, claims)
      auth_header = "Bearer #{jwt_token}"
      conn = build_conn([{"authorization", auth_header}], "GET")

      result = Authentication.ensure_project_accessible(conn, "account", "project", cache_name: cache_name)

      assert {:error, 403, _message} = result
    end
  end

  defp grants_auth_header(buckets) do
    claims = %{
      "cache_grants" => %{
        "project" => %{
          "read" => Keyword.get(buckets, :read, []),
          "write" => Keyword.get(buckets, :write, [])
        }
      },
      "exp" => System.system_time(:second) + 3600,
      "iat" => System.system_time(:second),
      "sub" => "user-123",
      "typ" => Keyword.get(buckets, :typ, "cache")
    }

    {:ok, jwt_token, _claims} = Cache.Guardian.encode_and_sign(%{}, claims)
    "Bearer #{jwt_token}"
  end

  defp request(cache_name, method, project \\ "project") do
    Authentication.ensure_project_accessible(
      build_conn([{"authorization", @test_auth_header}], method),
      "account",
      project,
      cache_name: cache_name
    )
  end

  defp confirm(cache_name, method, body) do
    stub_api_call(200, body)
    request(cache_name, method)
  end

  defp count_and_respond(status) do
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Authentication, fn conn ->
      Agent.update(counter, &(&1 + 1))
      Plug.Conn.send_resp(conn, status, "")
    end)

    counter
  end

  defp respond_with(:html), do: Req.Test.stub(Authentication, &Req.Test.html(&1, "<html>Bad gateway</html>"))

  defp respond_with(reason) when is_atom(reason),
    do: Req.Test.stub(Authentication, &Req.Test.transport_error(&1, reason))

  defp respond_with(status), do: stub_api_call(status, nil)

  defp build_conn(headers, method) do
    %{build_conn(headers) | method: method}
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
