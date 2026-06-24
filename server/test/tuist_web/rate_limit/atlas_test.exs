defmodule TuistWeb.RateLimit.AtlasTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistWeb.RateLimit.Atlas
  alias TuistWeb.RateLimit.InMemory

  describe "hit/1" do
    test "uses an Atlas-specific IP key", %{conn: conn} do
      ip = "127.0.0.1"
      timeout = to_timeout(minute: 1)
      bucket_size = 600

      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Tuist.Environment, :atlas_rate_limit_bucket_size, fn -> bucket_size end)

      expect(InMemory, :hit, fn "atlas:ip:127.0.0.1", ^timeout, ^bucket_size ->
        {:allow, 1}
      end)

      assert Atlas.hit(conn) == {:allow, 1}
    end
  end
end
