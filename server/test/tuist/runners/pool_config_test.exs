defmodule Tuist.Runners.PoolConfigTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Runners.PoolConfig

  @sample_pool %{
    name: "tuist",
    role: :customer,
    account_id: nil,
    owner: "tuist",
    labels: ["self-hosted", "macOS", "tuist-staging-macos"],
    max_concurrent: nil
  }

  @shared_warm_pool %{
    name: "warm-standby",
    role: :shared_warm,
    account_id: nil,
    owner: "",
    labels: [],
    max_concurrent: nil
  }

  describe "find_by_name/1" do
    test "returns nil for unknown pool" do
      # find_by_name reads pools/0 which is empty in :test env;
      # asserting the empty case is enough to guard the wiring.
      assert PoolConfig.find_by_name("does-not-exist") == nil
    end
  end

  describe "match_for_dispatch/3" do
    test "matches on owner + dispatch label" do
      assert {:ok, %{name: "tuist"}} =
               PoolConfig.match_for_dispatch(
                 "tuist",
                 ["self-hosted", "tuist-staging-macos"],
                 [@sample_pool]
               )
    end

    test "matches case-insensitively" do
      assert {:ok, %{name: "tuist"}} =
               PoolConfig.match_for_dispatch(
                 "Tuist",
                 ["TUIST-STAGING-MACOS"],
                 [@sample_pool]
               )
    end

    test "returns :no_match for an unknown owner" do
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch("acme", ["self-hosted"], [@sample_pool])
    end

    test "returns :no_match when only generic labels are requested" do
      # `self-hosted` and `macOS` are advertised on the runner but
      # are not authorization boundaries — without the pool's
      # tuist-staging-macos tag in the request the pool must not bind.
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch(
                 "tuist",
                 ["self-hosted", "macOS"],
                 [@sample_pool]
               )
    end

    test "returns :no_match when labels don't include dispatch_label" do
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch(
                 "tuist",
                 ["windows-latest"],
                 [@sample_pool]
               )
    end

    test "skips SharedWarm pools" do
      # SharedWarm pools are not customer-facing — even if a
      # workflow's labels somehow line up, the matcher must not
      # bind them. Bursts route via the customer pool that
      # matched; the warm pool only ever claims at dispatch time.
      assert {:error, :no_match} =
               PoolConfig.match_for_dispatch(
                 "tuist",
                 ["self-hosted", "tuist-staging-macos"],
                 [@shared_warm_pool]
               )
    end
  end

  describe "dispatch_label/1" do
    test "returns the last (pool-unique) label" do
      assert PoolConfig.dispatch_label(@sample_pool) == "tuist-staging-macos"
    end
  end

  describe "repo_allowed?/2" do
    test "allows every repo when allowed_repos is nil" do
      assert :ok = PoolConfig.repo_allowed?(%{allowed_repos: nil}, "tuist/tuist")
    end

    test "allows every repo when allowed_repos is empty" do
      assert :ok = PoolConfig.repo_allowed?(%{allowed_repos: []}, "tuist/tuist")
    end

    test "matches case-insensitively when repo is on the list" do
      pool = %{allowed_repos: ["tuist/tuist", "tuist/Cli"]}
      assert :ok = PoolConfig.repo_allowed?(pool, "TUIST/cli")
    end

    test "rejects when repo is not on the list" do
      pool = %{allowed_repos: ["tuist/tuist"]}

      assert {:error, :repo_not_allowed} =
               PoolConfig.repo_allowed?(pool, "acme/widgets")
    end
  end
end
