defmodule TuistWeb.RateLimit.InMemoryTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.RateLimit.InMemory

  describe "hit/4" do
    test "counts a fixed-window hit once on the serving node" do
      key = "local-fixed-window-hit-#{System.unique_integer([:positive])}"
      window = to_timeout(minute: 1)

      assert {:allow, 1} = InMemory.hit(key, window, 10)
      :sys.get_state(InMemory.Listener)

      assert {:allow, 2} = InMemory.Local.hit(key, window, 10)
    end
  end

  describe "hit_token_bucket/4" do
    test "counts a token-bucket hit once on the serving node" do
      key = "local-token-bucket-hit-#{System.unique_integer([:positive])}"
      refill_rate = 1 / 60

      assert {:allow, 9} = InMemory.hit_token_bucket(key, refill_rate, 10)
      :sys.get_state(InMemory.Listener)

      assert {:allow, 8} = InMemory.TokenBucket.hit(key, refill_rate, 10)
    end
  end
end
