defmodule TuistWeb.RateLimit.AuthTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.Auth

  describe "hit/1" do
    test "uses the authentication token-bucket policy", %{conn: conn} do
      ip = "127.0.0.1"
      refill_rate = 1 / 60

      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)

      expect(RateLimit, :hit, fn
        "auth:127.0.0.1", [algorithm: :token_bucket, refill_rate: ^refill_rate, capacity: 10] ->
          {:allow, 9}
      end)

      assert Auth.hit(conn) == {:allow, 9}
    end
  end
end
