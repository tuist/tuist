defmodule Tuist.Runners.VolumePrefetchTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.VolumePrefetch

  setup :verify_on_exit!

  # A Node carries its CAPI fleet; jobs are queued and recorded under the
  # RunnerPools that schedule onto it, as in production.
  @fleet "tuist-tuist-runners-fleet"
  @pool "macos-26-6"
  @other_pool "macos-27-0"
  @tree String.duplicate("a", 40)

  setup do
    stub(Tuist.Storage, :generate_download_url, fn key, _account, _opts -> "https://objects.example/#{key}" end)
    stub(Jobs, :pick_queued_top_k, fn _fleet, _accounts, _repositories, _jobs, _k -> {:error, :empty} end)
    stub(K8sClient, :list_runner_pools, fn _namespace -> {:ok, runner_pools()} end)
    :ok
  end

  defp runner_pools do
    [
      runner_pool(@pool, @fleet),
      runner_pool(@other_pool, @fleet),
      runner_pool("macos-26-6-elsewhere", "tuist-tuist-builders-fleet"),
      runner_pool("linux-4vcpu-16gb", @fleet)
    ]
  end

  defp runner_pool(name, fleet_selector) do
    %{"metadata" => %{"name" => name}, "spec" => %{"fleetSelector" => fleet_selector}}
  end

  @m2 %{"cpu" => "8", "memory" => "14Gi"}
  @m4 %{"cpu" => "12", "memory" => "28Gi"}

  defp fleet_node(name, labels, capacity \\ @m2) do
    %{"metadata" => %{"name" => name, "labels" => labels}, "status" => %{"capacity" => capacity}}
  end

  # The Nodes of one fleet, as the apiserver lists them by its label.
  defp stub_fleet(nodes) do
    stub(K8sClient, :get_node, fn name ->
      case Enum.find(nodes, &(get_in(&1, ["metadata", "name"]) == name)) do
        nil -> {:error, :not_found}
        node -> {:ok, node}
      end
    end)

    stub(K8sClient, :list_nodes, fn "tuist.dev/fleet=" <> _ -> {:ok, %{"items" => nodes}} end)
  end

  defp stub_node(labels), do: stub_fleet([fleet_node("mac-01", labels)])

  defp mac_labels(extra \\ %{}) do
    Map.merge(%{"tuist.dev/fleet" => @fleet, "tuist.dev/cache-volumes-per-repository" => "true"}, extra)
  end

  defp publish_head(account, volume \\ "tuist-cache") do
    {:ok, generation} = VolumeHeads.bump_head(account.id, "mac-02", @tree, 0, volume)
    generation
  end

  defp ran_recently(account, repository, fleet \\ @pool, node_name \\ "mac-01") do
    now = DateTime.utc_now()

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      node_name: node_name,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: fleet,
      repository: repository,
      pod_name: "pod-#{System.unique_integer([:positive])}",
      started_at: now,
      inserted_at: DateTime.truncate(now, :second),
      updated_at: DateTime.truncate(now, :second)
    })
  end

  defp queue(jobs) do
    jobs = Enum.map(jobs, &Map.put_new(&1, :enqueued_at, DateTime.utc_now()))

    stub(Jobs, :pick_queued_top_k, fn
      @pool, [], [], [], _k -> {:ok, jobs}
      _pool, [], [], [], _k -> {:error, :empty}
    end)
  end

  describe "node_for_service_account/2" do
    test "names the Node of a host's own ServiceAccount" do
      assert VolumePrefetch.node_for_service_account("tuist", "tart-kubelet-mac-01") == {:ok, "mac-01"}
    end

    test "refuses any other ServiceAccount" do
      assert VolumePrefetch.node_for_service_account("tuist-runners", "tart-kubelet-mac-01") == :error
      assert VolumePrefetch.node_for_service_account("tuist", "tuist-runners-controller") == :error
      assert VolumePrefetch.node_for_service_account("tuist", "tart-kubelet-") == :error
    end
  end

  describe "for_node/1" do
    test "lists the fleet's queued volumes before the ones it ran recently" do
      queued = account_fixture()
      recent = account_fixture()
      queued_volume = VolumeHeads.volume_name_for_repository("queued/app")
      recent_volume = VolumeHeads.volume_name_for_repository("recent/app")
      publish_head(queued, queued_volume)
      publish_head(recent, recent_volume)
      ran_recently(recent, "recent/app")
      queue([%{account_id: queued.id, repository: "queued/app"}])
      stub_node(mac_labels())

      assert [first, second] = VolumePrefetch.for_node("mac-01")
      assert %{account_id: account_id, volume: ^queued_volume, generation: 1, digest: @tree} = first
      assert account_id == queued.id
      assert first.download_url =~ "runner-volume-masters/#{queued.id}/#{queued_volume}/"
      assert %{volume: ^recent_volume} = second
      assert second.account_id == recent.id
    end

    test "leaves out the volumes the Node already holds" do
      account = account_fixture()
      publish_head(account)
      ran_recently(account, "")
      stub_node(mac_labels(%{"tuist.dev/cache-master-#{account.id}" => "true"}))

      assert VolumePrefetch.for_node("mac-01") == []
    end

    test "falls back to the account volume a new repository volume is seeded from" do
      account = account_fixture()
      publish_head(account)
      queue([%{account_id: account.id, repository: "acme/new-repo"}])
      stub_node(mac_labels())

      assert [%{volume: "tuist-cache"}] = VolumePrefetch.for_node("mac-01")
    end

    test "does not fall back past an account volume the Node holds" do
      account = account_fixture()
      publish_head(account)
      queue([%{account_id: account.id, repository: "acme/new-repo"}])
      stub_node(mac_labels(%{"tuist.dev/cache-master-#{account.id}" => "true"}))

      assert VolumePrefetch.for_node("mac-01") == []
    end

    test "keeps a Node that does not read repository volumes on the account volume" do
      account = account_fixture()
      publish_head(account)
      publish_head(account, VolumeHeads.volume_name_for_repository("acme/app"))
      queue([%{account_id: account.id, repository: "acme/app"}])
      stub_node(%{"tuist.dev/fleet" => @fleet})

      assert [%{volume: "tuist-cache"}] = VolumePrefetch.for_node("mac-01")
    end

    test "skips volumes that have published no master" do
      account = account_fixture()
      queue([%{account_id: account.id, repository: "acme/app"}])
      stub_node(mac_labels())

      assert VolumePrefetch.for_node("mac-01") == []
    end

    test "uses every macOS pool that schedules onto the Node's fleet, and only those" do
      in_fleet = account_fixture()
      other_fleet = account_fixture()
      linux = account_fixture()
      for account <- [in_fleet, other_fleet, linux], do: publish_head(account)
      ran_recently(in_fleet, "", @other_pool)
      ran_recently(other_fleet, "", "macos-26-6-elsewhere")
      ran_recently(linux, "", "linux-4vcpu-16gb")
      stub_node(mac_labels())

      assert [%{account_id: account_id}] = VolumePrefetch.for_node("mac-01")
      assert account_id == in_fleet.id
    end

    test "answers nothing for a Node outside a macOS fleet" do
      account = account_fixture()
      publish_head(account)
      ran_recently(account, "", "linux-4vcpu-16gb")
      stub(K8sClient, :list_runner_pools, fn _namespace -> {:ok, [runner_pool("linux-4vcpu-16gb", "runners-linux")]} end)
      stub_node(%{"tuist.dev/fleet" => "runners-linux"})

      assert VolumePrefetch.for_node("mac-01") == []
    end

    test "counts only the jobs that ran on the Node's host class" do
      on_m2 = account_fixture()
      on_m4 = account_fixture()
      publish_head(on_m2)
      publish_head(on_m4)
      ran_recently(on_m2, "", @pool, "mac-01")
      ran_recently(on_m4, "", @pool, "m4-01")
      stub_fleet([fleet_node("mac-01", mac_labels()), fleet_node("m4-01", mac_labels(), @m4)])

      assert [%{account_id: m2_account}] = VolumePrefetch.for_node("mac-01")
      assert m2_account == on_m2.id
      assert [%{account_id: m4_account}] = VolumePrefetch.for_node("m4-01")
      assert m4_account == on_m4.id
    end

    test "leaves a volume another Node of the class already holds" do
      account = account_fixture()
      publish_head(account)
      queue([%{account_id: account.id, repository: ""}])
      held = mac_labels(%{"tuist.dev/cache-master-#{account.id}" => "true"})

      stub_fleet([fleet_node("mac-01", mac_labels()), fleet_node("mac-02", held)])
      assert VolumePrefetch.for_node("mac-01") == []

      # A copy on the other class does not count: those Nodes take other jobs.
      stub_fleet([fleet_node("mac-01", mac_labels()), fleet_node("m4-01", held, @m4)])
      assert [%{account_id: account_id}] = VolumePrefetch.for_node("mac-01")
      assert account_id == account.id
    end

    test "assigns each volume to one Node of the class" do
      account = account_fixture()
      publish_head(account)
      queue([%{account_id: account.id, repository: ""}])
      names = for i <- 1..6, do: "mac-0#{i}"
      stub_fleet(Enum.map(names, &fleet_node(&1, mac_labels())))

      assert [_] = Enum.filter(names, &(VolumePrefetch.for_node(&1) != []))
    end

    test "answers nothing for a Node it cannot read" do
      stub(K8sClient, :get_node, fn "mac-01" -> {:error, :not_found} end)

      assert VolumePrefetch.for_node("mac-01") == []
    end
  end
end
