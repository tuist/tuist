defmodule TuistWeb.RateLimit.AgentAuthTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.AgentAuth

  describe "hit/2" do
    test "uses token-bucket policies for both address and subject", %{conn: conn} do
      ip = "127.0.0.1"
      subject = "User@Example.com"
      subject_digest = :sha256 |> :crypto.hash("user@example.com") |> Base.encode16(case: :lower)
      subject_key = "agent_auth:subject:#{subject_digest}"
      address_refill_rate = 60 / (60 * 60)
      subject_refill_rate = 20 / (60 * 60)

      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)

      expect(RateLimit, :hit, fn
        "agent_auth:ip:127.0.0.1", [algorithm: :token_bucket, refill_rate: ^address_refill_rate, capacity: 60] ->
          {:allow, 1}
      end)

      expect(
        RateLimit,
        :hit,
        fn ^subject_key, [algorithm: :token_bucket, refill_rate: ^subject_refill_rate, capacity: 20] ->
          {:allow, 1}
        end
      )

      assert AgentAuth.hit(conn, subject) == {:allow, 1}
    end
  end

  describe "hit_registration/2" do
    test "uses flow-specific source and service limits", %{conn: conn} do
      address_refill_rate = 5 / (60 * 60)
      service_refill_rate = 100 / (60 * 60)

      stub(TuistWeb.RemoteIp, :get, fn ^conn -> "127.0.0.1" end)

      expect(RateLimit, :hit, fn
        "agent_auth:registration:anonymous:ip:127.0.0.1",
        [algorithm: :token_bucket, refill_rate: ^address_refill_rate, capacity: 5] ->
          {:allow, 1}
      end)

      expect(RateLimit, :hit, fn
        "agent_auth:service:anonymous", [algorithm: :token_bucket, refill_rate: ^service_refill_rate, capacity: 100] ->
          {:allow, 1}
      end)

      assert AgentAuth.hit_registration(conn, :anonymous) == {:allow, 1}
    end

    test "skips the source limit when no address is available", %{conn: conn} do
      refill_rate = 1000 / (60 * 60)

      stub(TuistWeb.RemoteIp, :get, fn ^conn -> nil end)

      expect(RateLimit, :hit, fn
        "agent_auth:service:identity_assertion", [algorithm: :token_bucket, refill_rate: ^refill_rate, capacity: 1000] ->
          {:allow, 1}
      end)

      assert AgentAuth.hit_registration(conn, :identity_assertion) == {:allow, 1}
    end
  end
end
