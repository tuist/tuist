defmodule Tuist.Runners.PoolConfigTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.PoolConfig

  @sample_pool %{
    name: "tuist-tuist",
    account_id: nil,
    owner: "tuist",
    repo: "tuist",
    labels: ["self-hosted", "macOS", "tuist-tuist-staging"],
    min_warm: 0,
    max_concurrent: 2
  }

  describe "find_by_name/1" do
    test "returns nil for unknown pool" do
      # find_by_name reads pools/0 which is empty in :test env;
      # asserting the empty case is enough to guard the wiring.
      assert PoolConfig.find_by_name("does-not-exist") == nil
    end
  end

  describe "match_for_dispatch/3" do
    test "matches when the pool's dispatch label is present" do
      assert {:ok, %{name: "tuist-tuist"}} =
               PoolConfig.match_for_dispatch(
                 "tuist/tuist",
                 ["self-hosted", "tuist-tuist-staging"],
                 [@sample_pool]
               )
    end

    test "matches case-insensitively" do
      assert {:ok, %{name: "tuist-tuist"}} =
               PoolConfig.match_for_dispatch(
                 "Tuist/Tuist",
                 ["TUIST-TUIST-STAGING"],
                 [@sample_pool]
               )
    end

    test "returns :no_match for an unknown repo" do
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch("acme/ios", ["self-hosted"], [@sample_pool])
    end

    test "returns :no_match when only generic labels are requested" do
      # `self-hosted` and `macOS` are advertised on the runner but
      # are not authorization boundaries — without the pool's
      # tuist-tuist-staging tag in the request the pool must not bind.
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch(
                 "tuist/tuist",
                 ["self-hosted", "macOS"],
                 [@sample_pool]
               )
    end

    test "returns :no_match when labels don't include dispatch_label" do
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch(
                 "tuist/tuist",
                 ["windows-latest"],
                 [@sample_pool]
               )
    end
  end

  describe "dispatch_label/1" do
    test "returns the last (pool-unique) label" do
      assert PoolConfig.dispatch_label(@sample_pool) == "tuist-tuist-staging"
    end
  end
end
