defmodule TuistWeb.RateLimit.InMemoryTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Hammer.ETS.FixWindow
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RemoteIp

  describe "rate_limit/2" do
    test "allows the request when the rate limit is not reached" do
      # Given
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)

      expect(FixWindow, :hit, fn
        _table, "dashboard:GET:/:account_handle/:project_handle/bundles/:bundle_id:ip:127.0.0.1", _window, 60, 1 ->
          {:allow, 1}
      end)

      conn =
        :get
        |> build_conn("/tuist/ios_app_with_frameworks/bundles/01973a7f")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)

      # When
      got = InMemory.rate_limit(conn, %{})

      # Then
      assert conn == got
    end

    test "raises TooManyRequestsError when the rate limit is reached" do
      # Given
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      expect(FixWindow, :hit, fn _table, _key, _window, 60, _increment -> {:deny, 1} end)
      conn = build_conn()

      # When
      assert_raise TuistWeb.Errors.TooManyRequestsError, fn ->
        InMemory.rate_limit(conn, %{})
      end
    end

    test "uses the authenticated user in the key" do
      # Given
      expect(Environment, :tuist_hosted?, fn -> true end)
      expect(Environment, :dashboard_rate_limit_bucket_size, fn -> 60 end)
      Mimic.reject(&RemoteIp.get/1)

      expect(FixWindow, :hit, fn _table, "dashboard:GET:/:account_handle:user:123", _window, 60, 1 ->
        {:allow, 1}
      end)

      conn =
        :get
        |> build_conn("/tuist")
        |> Plug.Conn.put_private(:phoenix_router, TuistWeb.Router)
        |> Authentication.put_current_user(%User{id: 123})

      # When
      got = InMemory.rate_limit(conn, %{})

      # Then
      assert conn == got
    end

    test "allows a route-specific limit override" do
      # Given
      expect(Environment, :tuist_hosted?, fn -> true end)
      Mimic.reject(&Environment.dashboard_rate_limit_bucket_size/0)
      expect(FixWindow, :hit, fn _table, _key, _window, 10, _increment -> {:allow, 1} end)
      conn = build_conn()

      # When
      got = InMemory.rate_limit(conn, limit: 10)

      # Then
      assert conn == got
    end

    test "does not check rate limit when on premise" do
      # Given
      Mimic.reject(&FixWindow.hit/5)

      expect(Environment, :tuist_hosted?, fn -> false end)
      conn = build_conn()

      # When
      got = InMemory.rate_limit(conn, %{})

      # Then
      assert conn == got
    end
  end

  describe "hit/4" do
    test "counts a hit once on the serving node" do
      # Given
      key = "local-hit-#{System.unique_integer([:positive])}"
      scale = to_timeout(minute: 1)

      # When
      assert {:allow, 1} = InMemory.hit(key, scale, 10)
      :sys.get_state(InMemory.Listener)

      # Then
      assert {:allow, 2} = InMemory.Local.hit(key, scale, 10)
    end
  end
end
