defmodule TuistWeb.RateLimit.AuthTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistWeb.RateLimit.Auth

  describe("hit/1") do
    test "uses the in memory rate limiter when Redis is not setup", %{conn: conn} do
      # Given
      ip = "127.0.0.1"
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Tuist.Environment, :redis_url, fn -> nil end)
      hit_key = "auth:#{ip}"
      timeout = to_timeout(minute: 1)

      expect(TuistWeb.RateLimit.InMemory, :hit, fn ^hit_key, ^timeout, 10 ->
        {:allow, 10}
      end)

      # When
      assert Auth.hit(conn) == {:allow, 10}
    end

    test "uses the persistent rate limiter when Redis is setup", %{conn: conn} do
      # Given
      ip = "127.0.0.1"
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      redis_url = "redis://user123:securepass@redis.example.com:6379/0"
      stub(Tuist.Environment, :redis_url, fn -> redis_url end)
      hit_key = "auth:#{ip}"
      fill_rate = 1 / 60

      expect(TuistWeb.RateLimit.PersistentTokenBucket, :hit, fn ^hit_key, ^fill_rate, 10, 1 ->
        {:allow, 10}
      end)

      # When
      assert Auth.hit(conn) == {:allow, 10}
    end
  end
end
