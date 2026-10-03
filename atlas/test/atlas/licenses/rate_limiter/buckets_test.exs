defmodule Atlas.Licenses.RateLimiter.BucketsTest do
  use ExUnit.Case, async: true

  alias Atlas.Licenses.RateLimiter.Buckets

  @limits %{max_attempts: 2, window_milliseconds: 60_000, max_buckets: 3}

  test "allows attempts up to the configured maximum within one window" do
    assert {:ok, buckets} = Buckets.check(Buckets.new(), "client", 0, @limits)
    assert {:ok, buckets} = Buckets.check(buckets, "client", 10, @limits)

    assert {{:error, _retry_after}, _buckets} = Buckets.check(buckets, "client", 20, @limits)
  end

  test "counts each identifier independently" do
    {:ok, buckets} = Buckets.check(Buckets.new(), "a", 0, @limits)
    {:ok, buckets} = Buckets.check(buckets, "a", 0, @limits)

    assert {:ok, _buckets} = Buckets.check(buckets, "b", 0, @limits)
  end

  test "reports retry-after as the whole seconds left in the window" do
    {:ok, buckets} = Buckets.check(Buckets.new(), "client", 0, @limits)
    {:ok, buckets} = Buckets.check(buckets, "client", 0, @limits)

    assert {{:error, 30}, _buckets} = Buckets.check(buckets, "client", 30_000, @limits)
  end

  test "reports at least one second of retry-after at the very end of a window" do
    {:ok, buckets} = Buckets.check(Buckets.new(), "client", 0, @limits)
    {:ok, buckets} = Buckets.check(buckets, "client", 0, @limits)

    assert {{:error, 1}, _buckets} = Buckets.check(buckets, "client", 59_999, @limits)
  end

  test "starts a fresh window once the previous one has elapsed" do
    {:ok, buckets} = Buckets.check(Buckets.new(), "client", 0, @limits)
    {:ok, buckets} = Buckets.check(buckets, "client", 0, @limits)
    assert {{:error, _retry_after}, buckets} = Buckets.check(buckets, "client", 100, @limits)

    assert {:ok, buckets} = Buckets.check(buckets, "client", 60_000, @limits)
    assert {:ok, _buckets} = Buckets.check(buckets, "client", 60_000, @limits)
  end

  test "the window is anchored to the first attempt, not the most recent one" do
    {:ok, buckets} = Buckets.check(Buckets.new(), "client", 0, @limits)
    {:ok, buckets} = Buckets.check(buckets, "client", 59_000, @limits)

    assert {{:error, 1}, _buckets} = Buckets.check(buckets, "client", 59_000, @limits)
  end

  test "refuses new identifiers once the store is full so it cannot grow unbounded" do
    buckets =
      Enum.reduce(["a", "b", "c"], Buckets.new(), fn identifier, buckets ->
        {:ok, buckets} = Buckets.check(buckets, identifier, 0, @limits)
        buckets
      end)

    assert {{:error, 60}, buckets} = Buckets.check(buckets, "d", 0, @limits)
    assert map_size(buckets) == 3

    assert {:ok, _buckets} = Buckets.check(buckets, "a", 0, @limits)
  end

  test "admits new identifiers again once full buckets expire" do
    buckets =
      Enum.reduce(["a", "b", "c"], Buckets.new(), fn identifier, buckets ->
        {:ok, buckets} = Buckets.check(buckets, identifier, 0, @limits)
        buckets
      end)

    assert {{:error, _retry_after}, buckets} = Buckets.check(buckets, "d", 0, @limits)
    assert {:ok, buckets} = Buckets.check(buckets, "d", 60_000, @limits)
    assert Map.keys(buckets) == ["d"]
  end

  test "prune/3 drops only the buckets whose window has elapsed" do
    {:ok, buckets} = Buckets.check(Buckets.new(), "old", 0, @limits)
    {:ok, buckets} = Buckets.check(buckets, "new", 30_000, @limits)

    assert Map.keys(Buckets.prune(buckets, 60_000, 60_000)) == ["new"]
  end
end
