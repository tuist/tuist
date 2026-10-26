defmodule Tuist.Runners.SitesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Sites
  alias Tuist.Runners.WorkflowJob

  setup :verify_on_exit!

  @image "ghcr.io/tuist/tuist-runner:macos-26-6-1.0.0"

  setup do
    prefix = Tuist.Environment.runners_macos_pool_name_prefix()
    site_pool = "#{prefix}-ber1-26-6"
    sibling_pool = "#{prefix}-ber1-27-0"

    stub(Tuist.Environment, :runners_site_pools, fn ->
      %{
        site_pool => %{site: "ber1", platform: :macos},
        sibling_pool => %{site: "ber1", platform: :macos},
        "#{prefix}-fra1-26-6" => %{site: "fra1", platform: :macos}
      }
    end)

    stub(Client, :get_runner_pool, fn _namespace, ^site_pool ->
      {:ok,
       %{
         "metadata" => %{"name" => site_pool},
         "spec" => %{
           "fleetSelector" => "tuist-rack-fleet",
           "image" => @image,
           "podCPUMilli" => 6000,
           "podMemoryMB" => 14_336
         }
       }}
    end)

    cache = :"runners_sites_#{System.unique_integer([:positive])}"
    start_supervised!({Cachex, name: cache})
    stub(Sites, :cache_name, fn -> cache end)

    %{site_pool: site_pool, sibling_pool: sibling_pool, prefix: prefix, account: account_fixture()}
  end

  defp rack_node(opts \\ []) do
    labels =
      if Keyword.get(opts, :golden, true),
        do: %{"tuist.dev/fleet" => "tuist-rack-fleet", golden_label(@image) => "true"},
        else: %{"tuist.dev/fleet" => "tuist-rack-fleet"}

    %{
      "metadata" => %{"name" => "ber1-runner-b02", "labels" => labels},
      "spec" => %{"unschedulable" => Keyword.get(opts, :unschedulable, false)},
      "status" => %{
        "conditions" => [%{"type" => "Ready", "status" => Keyword.get(opts, :ready, "True")}],
        "allocatable" => %{"cpu" => Keyword.get(opts, :cpu, "12"), "memory" => Keyword.get(opts, :memory, "28Gi")}
      }
    }
  end

  defp golden_label(image) do
    "tuist.dev/golden-" <> (:sha256 |> :crypto.hash(image) |> binary_part(0, 8) |> Base.encode16(case: :lower))
  end

  defp stub_nodes(nodes) do
    stub(Client, :list_nodes, fn "tuist.dev/fleet=tuist-rack-fleet", _opts -> {:ok, %{"items" => nodes}} end)
  end

  defp insert_job(account, workflow_job_id, fleet, status, opts) do
    now = DateTime.utc_now()

    Repo.insert!(%WorkflowJob{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: fleet,
      status: status,
      platform: "macos",
      vcpus: 6,
      memory_gb: 14,
      enqueued_at: DateTime.add(now, -Keyword.get(opts, :enqueued_seconds_ago, 0), :second),
      claimed_at: opts[:claimed_seconds_ago] && DateTime.add(now, -opts[:claimed_seconds_ago], :second)
    })
  end

  describe "status/1" do
    test "is up while a Ready, schedulable Node fits the pool's guest", %{site_pool: site_pool} do
      stub_nodes([rack_node()])

      assert Sites.status(site_pool) == :up
    end

    test "is down when the site's Nodes are not Ready", %{site_pool: site_pool} do
      stub_nodes([rack_node(ready: "Unknown"), rack_node(ready: "False")])

      assert Sites.status(site_pool) == {:down, :no_capacity}
    end

    test "is down when the site's Nodes are cordoned", %{site_pool: site_pool} do
      stub_nodes([rack_node(unschedulable: true)])

      assert Sites.status(site_pool) == {:down, :no_capacity}
    end

    test "is down when no Node is large enough for the pool's guest", %{site_pool: site_pool} do
      stub_nodes([rack_node(cpu: "4", memory: "28Gi"), rack_node(cpu: "12", memory: "8Gi")])

      assert Sites.status(site_pool) == {:down, :no_capacity}
    end

    test "is down when the site has no Nodes", %{site_pool: site_pool} do
      stub_nodes([])

      assert Sites.status(site_pool) == {:down, :no_capacity}
    end

    test "is up when the cluster cannot be read", %{site_pool: site_pool} do
      stub(Client, :list_nodes, fn _selector, _opts -> {:error, :timeout} end)

      assert Sites.status(site_pool) == :up
    end

    test "is up when a job has queued past the stall bound while the site runs other jobs", %{
      site_pool: site_pool,
      sibling_pool: sibling_pool,
      account: account
    } do
      stub_nodes([rack_node()])
      insert_job(account, 930_001, site_pool, "queued", enqueued_seconds_ago: 1_200)

      Repo.insert!(%Claim{
        pod_name: "#{sibling_pool}-runner-a",
        workflow_job_id: 930_002,
        account_id: account.id,
        fleet_name: sibling_pool,
        claimed_at: DateTime.add(DateTime.utc_now(), -3_600, :second),
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        lifecycle_state: "running"
      })

      assert Sites.status(site_pool) == :up
    end

    test "is up when the site claimed a job within the stall bound", %{site_pool: site_pool, account: account} do
      stub_nodes([rack_node()])
      insert_job(account, 930_003, site_pool, "queued", enqueued_seconds_ago: 1_200)
      insert_job(account, 930_004, site_pool, "completed", enqueued_seconds_ago: 900, claimed_seconds_ago: 300)

      assert Sites.status(site_pool) == :up
    end

    test "is stalled when a job outwaits the bound and nothing at the site claims", %{
      site_pool: site_pool,
      prefix: prefix,
      account: account
    } do
      stub_nodes([rack_node()])
      insert_job(account, 930_005, site_pool, "queued", enqueued_seconds_ago: 700)
      insert_job(account, 930_006, "#{prefix}-fra1-26-6", "completed", enqueued_seconds_ago: 120, claimed_seconds_ago: 60)

      assert Sites.status(site_pool) == {:down, :stalled}
    end

    test "waits longer while no Node holds the pool's golden image", %{site_pool: site_pool, account: account} do
      stub_nodes([rack_node(golden: false)])
      insert_job(account, 930_007, site_pool, "queued", enqueued_seconds_ago: 1_200)

      assert Sites.status(site_pool) == :up
    end

    test "is stalled once a cold pull outlasts its bound", %{site_pool: site_pool, account: account} do
      stub_nodes([rack_node(golden: false)])
      insert_job(account, 930_008, site_pool, "queued", enqueued_seconds_ago: 1_900)

      assert Sites.status(site_pool) == {:down, :stalled}
    end
  end

  describe "available?/1" do
    test "answers from the cached status", %{site_pool: site_pool} do
      expect(Client, :list_nodes, 1, fn _selector, _opts -> {:ok, %{"items" => []}} end)

      refute Sites.available?(site_pool)
      refute Sites.available?(site_pool)
    end
  end

  describe "claim_site/2" do
    # The Node's site is cached by Node name, so each test reads its own Node.
    setup do
      %{node: "larch-runner-#{System.unique_integer([:positive])}"}
    end

    test "is the claiming Node's rack site", %{site_pool: site_pool, node: node} do
      expect(Client, :get_node, fn ^node, _opts ->
        {:ok, %{"metadata" => %{"labels" => %{"node.cluster.x-k8s.io/rack-site" => "larch"}}}}
      end)

      assert Sites.claim_site(site_pool, node) == "larch"
    end

    test "reads each Node once", %{site_pool: site_pool, node: node} do
      expect(Client, :get_node, 1, fn ^node, _opts ->
        {:ok, %{"metadata" => %{"labels" => %{"node.cluster.x-k8s.io/rack-site" => "larch"}}}}
      end)

      assert Sites.claim_site(site_pool, node) == "larch"
      assert Sites.claim_site(site_pool, node) == "larch"
    end

    test "is the pool's site for a Node without the label", %{site_pool: site_pool, node: node} do
      expect(Client, :get_node, fn ^node, _opts -> {:ok, %{"metadata" => %{"labels" => %{}}}} end)

      assert Sites.claim_site(site_pool, node) == "ber1"
    end

    test "is the pool's site while the Node cannot be read, and reads it again next time", %{
      site_pool: site_pool,
      node: node
    } do
      expect(Client, :get_node, fn ^node, _opts -> {:error, :timeout} end)

      assert Sites.claim_site(site_pool, node) == "ber1"

      expect(Client, :get_node, fn ^node, _opts ->
        {:ok, %{"metadata" => %{"labels" => %{"node.cluster.x-k8s.io/rack-site" => "larch"}}}}
      end)

      assert Sites.claim_site(site_pool, node) == "larch"
    end

    test "is the pool's site when the Pod's Node is unknown", %{site_pool: site_pool} do
      reject(&Client.get_node/2)

      assert Sites.claim_site(site_pool, nil) == "ber1"
    end

    test "is nil off the rack without reading the Node" do
      reject(&Client.get_node/2)

      assert Sites.claim_site("tuist-runner-pool-linux-4vcpu-16gb", "linux-node-1") == nil
    end
  end

  describe "prefer_cache_site/3" do
    setup %{account: account} do
      now = ~U[2026-10-26 12:00:00Z]
      warm_elsewhere = account_fixture()

      young = %{workflow_job_id: 1, account_id: warm_elsewhere.id, enqueued_at: DateTime.add(now, -59, :second)}
      old = %{workflow_job_id: 2, account_id: warm_elsewhere.id, enqueued_at: DateTime.add(now, -60, :second)}
      other = %{workflow_job_id: 3, account_id: account.id, enqueued_at: DateTime.add(now, -1, :second)}

      %{now: now, warm_elsewhere: warm_elsewhere, young: young, old: old, other: other}
    end

    test "leaves a young job of an account whose runner cache is warm at another site to that site", %{
      now: now,
      warm_elsewhere: warm_elsewhere,
      young: young,
      old: old,
      other: other
    } do
      expect(Tuist.Kura, :runner_cache_elsewhere, fn account_ids, "larch" ->
        assert Enum.sort(account_ids) == Enum.sort([warm_elsewhere.id, other.account_id])
        MapSet.new([warm_elsewhere.id])
      end)

      assert Sites.prefer_cache_site([young, old, other], "larch", now) == [old, other]
    end

    test "keeps every job when no account's cache is warm elsewhere", %{now: now, young: young, other: other} do
      expect(Tuist.Kura, :runner_cache_elsewhere, fn _account_ids, "ber1" -> MapSet.new() end)

      assert Sites.prefer_cache_site([young, other], "ber1", now) == [young, other]
    end

    test "passes over every job, so the runner waits, when all are young and warm elsewhere", %{
      now: now,
      warm_elsewhere: warm_elsewhere,
      young: young
    } do
      expect(Tuist.Kura, :runner_cache_elsewhere, fn _account_ids, "larch" -> MapSet.new([warm_elsewhere.id]) end)

      assert Sites.prefer_cache_site([young], "larch", now) == []
    end

    test "keeps every job for a runner off the rack", %{now: now, young: young} do
      reject(&Tuist.Kura.runner_cache_elsewhere/2)

      assert Sites.prefer_cache_site([young], nil, now) == [young]
    end

    test "reads nothing for an empty queue" do
      reject(&Tuist.Kura.runner_cache_elsewhere/2)

      assert Sites.prefer_cache_site([], "ber1") == []
    end
  end
end
