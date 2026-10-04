defmodule Tuist.ClickHouse.ReadRouteTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.ClickHouse.ReadRoute
  alias Tuist.ClickHouseRepo
  alias Tuist.ShadowClickHouseRepo
  alias TuistTestSupport.InClusterReads

  describe "enabled?/0" do
    test "is off when no in-cluster ClickHouse is configured" do
      # Which is every environment that is not mid-migration. The flag alone
      # must not be able to route reads at a server that is not there.
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> nil end)

      refute ReadRoute.enabled?()
    end

    test "is off when the URL is set but the instance is not running" do
      # The pool is started at boot from the same setting, so this is the
      # window during a rollout when configuration and process disagree.
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> "http://clickhouse:8123/tuist" end)

      refute ReadRoute.enabled?()
    end
  end

  describe "route/1" do
    test "leaves the read where it already went while routing is off" do
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> nil end)

      assert ReadRoute.route(fn -> ClickHouseRepo.get_dynamic_repo() end) ==
               ClickHouseRepo.get_dynamic_repo()
    end

    test "returns the read's value" do
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> nil end)

      assert ReadRoute.route(fn -> :result end) == :result
    end
  end

  describe "primary/1" do
    setup do
      InClusterReads.route_reads_in_cluster()
    end

    test "keeps reads on the system of record while routing is on" do
      default = ClickHouseRepo.get_dynamic_repo()

      assert ReadRoute.route(fn -> ClickHouseRepo.get_dynamic_repo() end) == ShadowClickHouseRepo
      assert ReadRoute.primary(fn -> ReadRoute.route(fn -> ClickHouseRepo.get_dynamic_repo() end) end) == default
    end

    test "stays on the system of record until the outermost call returns" do
      default = ClickHouseRepo.get_dynamic_repo()

      assert ReadRoute.primary(fn ->
               ReadRoute.primary(fn -> :ok end)
               ReadRoute.route(fn -> ClickHouseRepo.get_dynamic_repo() end)
             end) == default
    end

    test "routes reads again once it returns" do
      ReadRoute.primary(fn -> :ok end)

      refute ReadRoute.primary?()
      assert ReadRoute.route(fn -> ClickHouseRepo.get_dynamic_repo() end) == ShadowClickHouseRepo
    end

    test "stops routing even when the read raises" do
      assert_raise RuntimeError, fn -> ReadRoute.primary(fn -> raise "read failed" end) end

      refute ReadRoute.primary?()
    end
  end
end
