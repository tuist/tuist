defmodule Tuist.Application.RuntimeChildrenTest do
  use ExUnit.Case, async: true

  alias Cluster.Strategy.Kubernetes.DNS
  alias Tuist.Application.RuntimeChildren
  alias Tuist.Environment

  describe "cluster/1" do
    test "starts discovery whenever a topology is configured" do
      topologies = [kubernetes: [strategy: DNS]]

      assert [{Cluster.Supervisor, [configured, [name: Tuist.ClusterSupervisor]]}] = RuntimeChildren.cluster(topologies)
      assert configured[:kubernetes][:strategy] == DNS
      assert configured[:kubernetes][:disconnect] == {RuntimeChildren, :retain_cluster_node, []}
      assert RuntimeChildren.retain_cluster_node(:discovery_peer) == true
    end

    test "preserves unrelated discovery strategies" do
      topologies = [static: [strategy: Cluster.Strategy.Epmd, config: [hosts: [:peer]]]]

      assert RuntimeChildren.cluster(topologies) ==
               [{Cluster.Supervisor, [topologies, [name: Tuist.ClusterSupervisor]]}]
    end

    test "DNS cannot reintroduce explicit disconnects through a custom topology" do
      topologies = [kubernetes: [strategy: DNS, disconnect: {:erlang, :disconnect_node, []}]]
      [{Cluster.Supervisor, [configured, _]}] = RuntimeChildren.cluster(topologies)
      assert configured[:kubernetes][:disconnect] == {RuntimeChildren, :retain_cluster_node, []}
    end

    test "does not start discovery without a topology" do
      assert RuntimeChildren.cluster([]) == []
    end
  end

  describe "guardian_db_sweeper/1" do
    test ":web starts the sweeper" do
      assert [{Guardian.DB.Sweeper, opts}] = RuntimeChildren.guardian_db_sweeper(:web)
      assert Keyword.fetch!(opts, :interval) > 0
    end

    test "every non-web mode returns no children" do
      for mode <- Environment.modes(), mode != :web do
        assert RuntimeChildren.guardian_db_sweeper(mode) == [],
               "expected no Guardian.DB.Sweeper child for #{inspect(mode)} — " <>
                 "non-web pods connect with a DB role that lacks privileges on " <>
                 "`guardian_tokens` and the sweeper would fail every interval " <>
                 "with `permission denied`"
      end
    end
  end

  describe "open_graph_image_renderer/1" do
    test ":web starts the renderer and its task supervisor" do
      children = RuntimeChildren.open_graph_image_renderer(:web)

      assert {Task.Supervisor, name: Tuist.OpenGraphImageRenderer.TaskSupervisor} in children
      assert Tuist.OpenGraphImageRenderer in children
    end

    test "every non-web mode returns no children" do
      for mode <- Environment.modes(), mode != :web do
        assert RuntimeChildren.open_graph_image_renderer(mode) == [],
               "expected no Tuist.OpenGraphImageRenderer child for #{inspect(mode)} — " <>
                 "non-web images have no Chrome installed, so Browse.Pool.init_worker/1 " <>
                 "raises :chrome_not_found and NimblePool retries it forever without backoff"
      end
    end
  end

  describe "marketing_stats/1" do
    test ":web starts the poller" do
      assert RuntimeChildren.marketing_stats(:web) == [Tuist.Marketing.Stats]
    end

    test "every non-web mode returns no children" do
      for mode <- Environment.modes(), mode != :web do
        assert RuntimeChildren.marketing_stats(mode) == [],
               "expected no Tuist.Marketing.Stats child for #{inspect(mode)} — " <>
                 "it polls marketing stats only to feed the marketing LiveViews, " <>
                 "which non-web pods never serve"
      end
    end
  end

  describe "agents/3" do
    defp runner?(children), do: Enum.any?(children, &match?(%{id: Tuist.Agents.Runner}, &1))

    test "agents pods and undelegated web pods host sessions; no other mode does" do
      for mode <- Environment.modes(), delegated? <- [false, true] do
        children = RuntimeChildren.agents(mode, delegated?, [])
        assert {DynamicSupervisor, name: Tuist.Agents.Hosts, strategy: :one_for_one} in children

        assert runner?(children) == (mode == :agents or (mode == :web and not delegated?)),
               "unexpected runner for mode=#{inspect(mode)} delegated?=#{delegated?}"
      end
    end

    # A web pod stops its runner only after the preStop wait and the endpoint
    # drain, so it must stop well inside the 60 s grace period.
    test "the runner stops within its pod's budget, after waiting for its sessions" do
      for {mode, budget} <- [agents: 30_000, web: 15_000] do
        [_hosts, %{shutdown: shutdown, start: {_, _, [opts]}}] = RuntimeChildren.agents(mode, false, [])
        assert shutdown == budget
        assert Keyword.fetch!(opts, :drain_ms) < shutdown
      end
    end

    test "a disabled runner is left out" do
      refute runner?(RuntimeChildren.agents(:agents, false, enabled: false))
    end
  end

  describe "readiness_server/1" do
    test ":xcresult_processor serves Tuist.Readiness.Plug on the readiness port" do
      assert [{Tuist.XcresultDrain, []}, {Plug.Cowboy, opts}] = RuntimeChildren.readiness_server(:xcresult_processor)
      assert Keyword.fetch!(opts, :plug) == Tuist.Readiness.Plug
      assert opts |> Keyword.fetch!(:options) |> Keyword.fetch!(:port) == Tuist.Readiness.port()
    end

    test "every other mode returns no children" do
      for mode <- Environment.modes(), mode != :xcresult_processor do
        assert RuntimeChildren.readiness_server(mode) == [],
               "expected no readiness listener for #{inspect(mode)}; only the xcresult processor is probed through it"
      end
    end
  end
end
