defmodule TuistWeb.RateLimit.AgentAuthTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistWeb.RateLimit.AgentAuth
  alias TuistWeb.RateLimit.InMemory

  describe "hit/2" do
    test "uses the in-memory rate limiter for both IP and subject when Redis is not setup", %{conn: conn} do
      ip = "127.0.0.1"
      subject = "User@Example.com"
      subject_digest = :sha256 |> :crypto.hash("user@example.com") |> Base.encode16(case: :lower)
      timeout = to_timeout(hour: 1)
      subject_key = "agent_auth:subject:#{subject_digest}"

      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Tuist.Environment, :redis_url, fn -> nil end)

      expect(InMemory, :hit, fn "agent_auth:ip:127.0.0.1", ^timeout, 60 ->
        {:allow, 1}
      end)

      expect(
        InMemory,
        :hit,
        fn ^subject_key, ^timeout, 20 ->
          {:allow, 1}
        end
      )

      assert AgentAuth.hit(conn, subject) == {:allow, 1}
    end

    test "uses the persistent rate limiter when Redis is setup", %{conn: conn} do
      ip = "127.0.0.1"
      fill_rate = 60 / (60 * 60)

      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Tuist.Environment, :redis_url, fn -> "redis://example" end)

      expect(
        TuistWeb.RateLimit.PersistentTokenBucket,
        :hit,
        fn "agent_auth:ip:127.0.0.1", ^fill_rate, 60, 1 ->
          {:allow, 1}
        end
      )

      assert AgentAuth.hit(conn) == {:allow, 1}
    end
  end
end
