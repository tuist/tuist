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

  describe "match_for_dispatch/3" do
    test "matches on repo + intersecting labels" do
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

    test "returns :no_match when labels don't intersect" do
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch(
                 "tuist/tuist",
                 ["windows-latest"],
                 [@sample_pool]
               )
    end
  end
end
