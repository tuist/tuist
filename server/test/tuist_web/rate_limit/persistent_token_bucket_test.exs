defmodule TuistWeb.RateLimit.PersistentTokenBucketTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistWeb.RateLimit.PersistentTokenBucket

  describe "hit_with_fallback/5" do
    test "returns the persistent bucket result when the call succeeds" do
      fill_rate = 1 / 60

      expect(PersistentTokenBucket, :hit, fn "key", ^fill_rate, 10, 1 ->
        {:allow, 9}
      end)

      assert PersistentTokenBucket.hit_with_fallback("key", fill_rate, 10, 1, fn ->
               {:allow, 1}
             end) == {:allow, 9}
    end

    test "uses the fallback when the persistent call times out" do
      fill_rate = 1 / 60

      expect(PersistentTokenBucket, :hit, fn "key", ^fill_rate, 10, 1 ->
        raise MatchError,
          term: {:error, %Redix.ConnectionError{reason: :timeout}}
      end)

      assert PersistentTokenBucket.hit_with_fallback("key", fill_rate, 10, 1, fn ->
               {:allow, 1}
             end) == {:allow, 1}
    end

    test "uses the fallback when the persistent connection exits" do
      fill_rate = 1 / 60

      expect(PersistentTokenBucket, :hit, fn "key", ^fill_rate, 10, 1 ->
        exit({:noproc, {GenServer, :call, []}})
      end)

      assert PersistentTokenBucket.hit_with_fallback("key", fill_rate, 10, 1, fn ->
               {:allow, 1}
             end) == {:allow, 1}
    end
  end
end
