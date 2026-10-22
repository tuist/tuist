defmodule TuistWeb.RateLimitTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.TooManyRequestsError
  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentFixedWindow
  alias TuistWeb.RateLimit.PersistentTokenBucket
  alias TuistWeb.RemoteIp

  describe "hit/2" do
    test "uses the fixed-window in-memory limiter when Valkey is not configured" do
      window = to_timeout(minute: 1)

      stub(Environment, :redis_url, fn -> nil end)

      expect(InMemory, :hit, fn "key", ^window, 10, 2 ->
        {:allow, 2}
      end)

      assert RateLimit.hit("key", limit: 10, window: window, increment: 2) == {:allow, 2}
    end

    test "uses the persistent fixed-window limiter when Valkey is configured" do
      window = to_timeout(minute: 1)

      stub(Environment, :redis_url, fn -> "redis://example" end)

      expect(PersistentFixedWindow, :hit, fn "key", ^window, 10, 1 ->
        {:allow, 1}
      end)

      assert RateLimit.hit("key", limit: 10, window: window) == {:allow, 1}
    end

    test "denies requests when the shared fixed-window limiter times out" do
      window = to_timeout(minute: 1)

      stub(Environment, :redis_url, fn -> "redis://example" end)

      expect(PersistentFixedWindow, :hit, fn "key", ^window, 10, 1 ->
        raise Redix.ConnectionError, reason: :timeout
      end)

      assert RateLimit.hit("key", limit: 10, window: window) == {:deny, window}
    end

    test "availability traffic uses a divided local budget when Valkey exits" do
      window = to_timeout(minute: 1)
      stub(Environment, :redis_url, fn -> "redis://example" end)
      expect(PersistentFixedWindow, :hit, fn "key", ^window, 100, 1 -> exit(:noproc) end)
      expect(InMemory, :hit, fn "fallback:key", ^window, 20, 1 -> {:allow, 1} end)
      assert RateLimit.hit("key", limit: 100, window: window, failure_policy: :local) == {:allow, 1}
    end

    test "an outage budget smaller than the replica allowance denies instead of multiplying the limit" do
      window = to_timeout(minute: 1)
      stub(Environment, :redis_url, fn -> "redis://example" end)
      expect(PersistentFixedWindow, :hit, fn "key", ^window, 1, 1 -> exit(:noproc) end)
      reject(InMemory, :hit, 4)
      assert RateLimit.hit("key", limit: 1, window: window, failure_policy: :local) == {:deny, window}
    end

    test "availability token buckets divide both capacity and refill on failure" do
      stub(Environment, :redis_url, fn -> "redis://example" end)
      expect(PersistentTokenBucket, :hit, fn "key", 10, 100, 1 -> exit(:noproc) end)
      expect(InMemory, :hit_token_bucket, fn "fallback:key", 2.0, 20, 1 -> {:allow, 19} end)

      assert RateLimit.hit("key", algorithm: :token_bucket, capacity: 100, refill_rate: 10, failure_policy: :local) ==
               {:allow, 19}
    end

    test "uses the token-bucket in-memory limiter when Valkey is not configured" do
      refill_rate = 1 / 60

      stub(Environment, :redis_url, fn -> nil end)

      expect(InMemory, :hit_token_bucket, fn "key", ^refill_rate, 10, 2 ->
        {:allow, 8}
      end)

      assert RateLimit.hit(
               "key",
               algorithm: :token_bucket,
               refill_rate: refill_rate,
               capacity: 10,
               cost: 2
             ) == {:allow, 8}
    end

    test "uses the persistent token-bucket limiter when Valkey is configured" do
      refill_rate = 1 / 60

      stub(Environment, :redis_url, fn -> "redis://example" end)

      expect(PersistentTokenBucket, :hit, fn "key", ^refill_rate, 10, 1 ->
        {:allow, 9}
      end)

      assert RateLimit.hit(
               "key",
               algorithm: :token_bucket,
               refill_rate: refill_rate,
               capacity: 10
             ) == {:allow, 9}
    end

    test "denies requests when the shared token-bucket limiter times out" do
      refill_rate = 1 / 60

      stub(Environment, :redis_url, fn -> "redis://example" end)

      expect(PersistentTokenBucket, :hit, fn "key", ^refill_rate, 10, 1 ->
        raise MatchError,
          term: {:error, %Redix.ConnectionError{reason: :timeout}}
      end)

      assert RateLimit.hit(
               "key",
               algorithm: :token_bucket,
               refill_rate: refill_rate,
               capacity: 10
             ) == {:deny, 60_000}
    end

    test "denies requests when the shared Valkey connection exits" do
      refill_rate = 1 / 60

      stub(Environment, :redis_url, fn -> "redis://example" end)

      expect(PersistentTokenBucket, :hit, fn "key", ^refill_rate, 10, 1 ->
        exit({:noproc, {GenServer, :call, []}})
      end)

      assert RateLimit.hit(
               "key",
               algorithm: :token_bucket,
               refill_rate: refill_rate,
               capacity: 10
             ) == {:deny, 60_000}
    end
  end

  describe "rate_limit/2" do
    test "allows the request when the rate limit is not reached" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      expect(Environment, :public_project_rate_limit_bucket_size, fn -> 120 end)

      expect(RateLimit, :hit, fn
        "dashboard:GET:/:account_handle/:project_handle/bundles/:bundle_id:ip:127.0.0.1",
        [limit: 60, window: _window, failure_policy: :local] ->
          {:allow, 1}
      end)

      expect(RateLimit, :hit, fn
        "dashboard:anon-scope:GET:tuist/ios_app_with_frameworks", [limit: 120, window: _window, failure_policy: :local] ->
          {:allow, 1}
      end)

      conn =
        :get
        |> build_conn("/tuist/ios_app_with_frameworks/bundles/01973a7f")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)
        |> Map.put(:path_params, %{"account_handle" => "tuist", "project_handle" => "ios_app_with_frameworks"})

      assert conn == RateLimit.rate_limit(conn, %{})
    end

    test "raises TooManyRequestsError when the rate limit is reached" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      expect(RateLimit, :hit, fn _key, _opts -> {:deny, 1} end)

      assert_raise TooManyRequestsError, fn ->
        RateLimit.rate_limit(build_conn(), %{})
      end
    end

    test "raises TooManyRequestsError when the anon per-scope limit is reached even if the per-IP limit allows" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      expect(Environment, :public_project_rate_limit_bucket_size, fn -> 120 end)

      expect(RateLimit, :hit, fn "dashboard:GET:" <> _rest, _opts -> {:allow, 1} end)
      expect(RateLimit, :hit, fn "dashboard:anon-scope:GET:tuist/ios_app_with_frameworks", _opts -> {:deny, 1} end)

      conn =
        :get
        |> build_conn("/tuist/ios_app_with_frameworks/tests/test-runs")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)
        |> Map.put(:path_params, %{"account_handle" => "tuist", "project_handle" => "ios_app_with_frameworks"})

      assert_raise TooManyRequestsError, fn ->
        RateLimit.rate_limit(conn, %{})
      end
    end

    test "keys the anon per-scope limit on the account when only an account handle is present" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      expect(Environment, :public_project_rate_limit_bucket_size, fn -> 120 end)

      expect(RateLimit, :hit, fn "dashboard:GET:" <> _rest, _opts -> {:allow, 1} end)
      expect(RateLimit, :hit, fn "dashboard:anon-scope:GET:tuist", _opts -> {:allow, 1} end)

      conn =
        :get
        |> build_conn("/tuist")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)
        |> Map.put(:path_params, %{"account_handle" => "tuist"})

      assert conn == RateLimit.rate_limit(conn, %{})
    end

    test "does not apply the anon per-scope limit when the request is authenticated" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      Mimic.reject(&Environment.public_project_rate_limit_bucket_size/0)
      Mimic.reject(&RemoteIp.get/1)

      expect(RateLimit, :hit, fn
        "dashboard:GET:/:account_handle:user:123", [limit: 60, window: _window, failure_policy: :local] ->
          {:allow, 1}
      end)

      conn =
        :get
        |> build_conn("/tuist")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)
        |> Map.put(:path_params, %{"account_handle" => "tuist"})
        |> Authentication.put_current_user(%User{id: 123})

      assert conn == RateLimit.rate_limit(conn, %{})
    end

    test "does not apply the anon per-scope limit when the request path carries no scope" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      Mimic.reject(&Environment.public_project_rate_limit_bucket_size/0)

      expect(RateLimit, :hit, fn _key, _opts -> {:allow, 1} end)

      conn =
        :get
        |> build_conn("/")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)

      assert conn == RateLimit.rate_limit(conn, %{})
    end

    test "uses the authenticated user in the key" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      Mimic.reject(&RemoteIp.get/1)

      expect(RateLimit, :hit, fn
        "dashboard:GET:/:account_handle:user:123", [limit: 60, window: _window, failure_policy: :local] ->
          {:allow, 1}
      end)

      conn =
        :get
        |> build_conn("/tuist")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)
        |> Authentication.put_current_user(%User{id: 123})

      assert conn == RateLimit.rate_limit(conn, %{})
    end

    test "allows a route-specific limit override" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      Mimic.reject(&Environment.dashboard_rate_limit_bucket_size/0)
      expect(RateLimit, :hit, fn _key, [limit: 10, window: _window, failure_policy: :local] -> {:allow, 1} end)
      conn = build_conn()

      assert conn == RateLimit.rate_limit(conn, limit: 10)
    end

    test "allows an anon per-scope limit override" do
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      Mimic.reject(&Environment.public_project_rate_limit_bucket_size/0)

      expect(RateLimit, :hit, fn "dashboard:GET:" <> _rest, _opts -> {:allow, 1} end)

      expect(RateLimit, :hit, fn "dashboard:anon-scope:GET:tuist/ios_app_with_frameworks",
                                 [limit: 42, window: _window, failure_policy: :local] ->
        {:allow, 1}
      end)

      conn =
        :get
        |> build_conn("/tuist/ios_app_with_frameworks/tests")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)
        |> Map.put(:path_params, %{"account_handle" => "tuist", "project_handle" => "ios_app_with_frameworks"})

      assert conn == RateLimit.rate_limit(conn, anon_scope_limit: 42)
    end

    test "does not check the rate limit when self-hosted" do
      Mimic.reject(&RateLimit.hit/2)
      expect(Environment, :tuist_hosted?, fn -> false end)
      conn = build_conn()

      assert conn == RateLimit.rate_limit(conn, %{})
    end
  end
end
