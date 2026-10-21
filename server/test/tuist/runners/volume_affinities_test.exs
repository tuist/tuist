defmodule Tuist.Runners.VolumeAffinitiesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.VolumeAffinities
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup do
    # Residency is cached per node to keep the apiserver read off the dispatch
    # path. Bypass it here so each case exercises the label parsing rather than
    # a neighbouring case's cached answer for the same node name.
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    :ok
  end

  # A Node as tart-kubelet advertises it: one `tuist.dev/cache-master-<id>`
  # label per resident master, alongside the golden-image labels it already
  # publishes on the same heartbeat.
  defp node_with_masters(account_ids, extra_labels \\ %{}) do
    labels =
      account_ids
      |> Map.new(fn id -> {"tuist.dev/cache-master-#{id}", "true"} end)
      |> Map.merge(extra_labels)

    {:ok, %{"metadata" => %{"labels" => labels}}}
  end

  describe "resident_masters/1" do
    test "reads the account ids the host advertises" do
      stub(K8sClient, :get_node, fn "mac-01" -> node_with_masters([42, 7]) end)

      assert VolumeAffinities.resident_masters("mac-01") == MapSet.new([{42, "tuist-cache"}, {7, "tuist-cache"}])
    end

    test "reads the repository volumes the host advertises" do
      stub(K8sClient, :get_node, fn "mac-01" ->
        node_with_masters([42], %{
          "tuist.dev/cache-master-42.repo-eae044a4c27633ea" => "true",
          "tuist.dev/cache-master-7.repo-5f89da0438fa1b17" => "true",
          "tuist.dev/cache-master-7.not-a-volume" => "true"
        })
      end)

      assert VolumeAffinities.resident_masters("mac-01") ==
               MapSet.new([{42, "tuist-cache"}, {42, "repo-eae044a4c27633ea"}, {7, "repo-5f89da0438fa1b17"}])
    end

    test "ignores labels that are not cache-master advertisements" do
      stub(K8sClient, :get_node, fn "mac-01" ->
        node_with_masters([42], %{
          "tuist.dev/golden-abc123" => "true",
          "tuist.dev/runtime" => "tart",
          "kubernetes.io/os" => "darwin"
        })
      end)

      assert VolumeAffinities.resident_masters("mac-01") == MapSet.new([{42, "tuist-cache"}])
    end

    test "ignores a cache-master label whose suffix is not an account id" do
      stub(K8sClient, :get_node, fn "mac-01" ->
        node_with_masters([42], %{"tuist.dev/cache-master-not-an-id" => "true"})
      end)

      assert VolumeAffinities.resident_masters("mac-01") == MapSet.new([{42, "tuist-cache"}])
    end

    test "returns an empty set when the node is unreadable" do
      # Degrades to no preference rather than failing dispatch: a host we cannot
      # read is simply handed plain oldest-queued work.
      stub(K8sClient, :get_node, fn _ -> {:error, :not_found} end)

      assert VolumeAffinities.resident_masters("mac-01") == MapSet.new()
    end

    test "returns an empty set without node identity" do
      reject(&K8sClient.get_node/1)

      assert VolumeAffinities.resident_masters(nil) == MapSet.new()
      assert VolumeAffinities.resident_masters("") == MapSet.new()
    end

    test "returns an empty set for a host advertising no masters" do
      stub(K8sClient, :get_node, fn _ -> node_with_masters([]) end)

      assert VolumeAffinities.resident_masters("mac-01") == MapSet.new()
    end
  end

  describe "repository_volumes?/1" do
    test "is true for a host that advertises repository volumes" do
      stub(K8sClient, :get_node, fn "mac-01" ->
        node_with_masters([42], %{"tuist.dev/cache-volumes-per-repository" => "true"})
      end)

      assert VolumeAffinities.repository_volumes?("mac-01")
    end

    test "is false for a host that does not, or cannot be read" do
      stub(K8sClient, :get_node, fn
        "mac-01" -> node_with_masters([42])
        "mac-02" -> {:error, :not_found}
      end)

      refute VolumeAffinities.repository_volumes?("mac-01")
      refute VolumeAffinities.repository_volumes?("mac-02")
      refute VolumeAffinities.repository_volumes?(nil)
    end
  end

  describe "select_candidate/3" do
    setup do
      %{account: 4242, other: 7777}
    end

    defp stub_residency(account_ids) do
      stub(K8sClient, :get_node, fn _ -> node_with_masters(account_ids) end)
    end

    test "returns nil for no candidates" do
      assert VolumeAffinities.select_candidate([], "mac-01", tolerance_seconds: 30) == nil
    end

    test "returns the head when the node holds no masters", %{account: account, other: other} do
      stub_residency([])
      now = DateTime.utc_now()
      head = %{account_id: other, enqueued_at: now}
      resident = %{account_id: account, enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {head, :no_residency}
    end

    test "prefers a resident account's job while the head is within the tolerance", %{
      account: account,
      other: other
    } do
      stub_residency([account])
      now = DateTime.utc_now()
      head = %{account_id: other, enqueued_at: now}
      resident = %{account_id: account, enqueued_at: DateTime.add(now, 10, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {resident, :resident}
    end

    test "does not prefer an account whose master the host has evicted", %{account: account, other: other} do
      evicted = 999

      # The host advertises what is on disk, so an evicted master simply stops
      # appearing. This is the case a dispatch-history model could not see: the
      # account may well have run here most recently.
      stub_residency([account, other])
      now = DateTime.utc_now()
      head = %{account_id: account, enqueued_at: now}
      evicted_candidate = %{account_id: evicted, enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, evicted_candidate], "mac-01", tolerance_seconds: 30) ==
               {head, :head_resident}
    end

    test "reports when nothing queued matches the node's masters", %{account: account, other: other} do
      stub_residency([account])
      now = DateTime.utc_now()
      head = %{account_id: other, enqueued_at: now}

      assert VolumeAffinities.select_candidate([head], "mac-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end

    test "affinity wins regardless of the enqueue gap to the head, as long as the head is fresh",
         %{account: account, other: other} do
      stub_residency([account])
      now = DateTime.utc_now()
      # Far newer than the head, but the head itself has waited ~0s, so the
      # bound is on head age (from now), not the candidate-vs-head gap.
      head = %{account_id: other, enqueued_at: now}
      resident = %{account_id: account, enqueued_at: DateTime.add(now, 300, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {resident, :resident}
    end

    test "falls back to the head once the head has waited past the tolerance", %{
      account: account,
      other: other
    } do
      stub_residency([account])
      now = DateTime.utc_now()
      # Head was enqueued 60s ago, exceeding the 30s tolerance: it must be
      # handed out now even though a resident candidate exists. This is the
      # burst-starvation bound — a run of resident jobs can't pass the head
      # over indefinitely, because the head's own age caps the delay.
      head = %{account_id: other, enqueued_at: DateTime.add(now, -60, :second)}
      resident = %{account_id: account, enqueued_at: DateTime.add(now, -50, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {head, :head_overdue}
    end

    test "an overdue head with nothing resident queued is not blamed on the starvation bound", %{
      account: account,
      other: other
    } do
      stub_residency([account])
      now = DateTime.utc_now()
      # Overdue, but there was no resident candidate to give up, so the bound
      # cost nothing. Reporting :head_overdue here would overstate what the
      # tolerance is costing and push it to be raised for no gain.
      head = %{account_id: other, enqueued_at: DateTime.add(now, -60, :second)}

      assert VolumeAffinities.select_candidate([head], "mac-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end

    test "the starvation bound holds no matter how many resident jobs are queued ahead of it", %{
      account: account,
      other: other
    } do
      stub_residency([account])
      now = DateTime.utc_now()
      head = %{account_id: other, enqueued_at: DateTime.add(now, -31, :second)}

      residents =
        for offset <- 1..20, do: %{account_id: account, enqueued_at: DateTime.add(now, -30 + offset, :second)}

      assert {^head, :head_overdue} =
               VolumeAffinities.select_candidate([head | residents], "mac-01", tolerance_seconds: 30)
    end

    test "matches a candidate on its repository's volume", %{account: account} do
      stub(K8sClient, :get_node, fn _ ->
        node_with_masters([], %{"tuist.dev/cache-master-#{account}.repo-eae044a4c27633ea" => "true"})
      end)

      now = DateTime.utc_now()
      head = %{account_id: account, repository: "acme/app", enqueued_at: now}
      resident = %{account_id: account, repository: "acme/cli", enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {resident, :resident}
    end

    test "counts the account's volume as resident for a repository volume it can seed", %{
      account: account,
      other: other
    } do
      stub_residency([account])
      now = DateTime.utc_now()
      head = %{account_id: other, repository: "other/app", enqueued_at: now}
      seedable = %{account_id: account, repository: "acme/cli", enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, seedable], "mac-01", tolerance_seconds: 30) ==
               {seedable, :resident}
    end

    test "does not count a repository volume as resident for a job with no repository", %{
      account: account,
      other: other
    } do
      stub(K8sClient, :get_node, fn _ ->
        node_with_masters([], %{"tuist.dev/cache-master-#{account}.repo-eae044a4c27633ea" => "true"})
      end)

      now = DateTime.utc_now()
      head = %{account_id: other, repository: "", enqueued_at: now}
      no_repository = %{account_id: account, repository: "", enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, no_repository], "mac-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end

    test "returns the oldest resident candidate when several are resident", %{account: account} do
      stub_residency([account])
      now = DateTime.utc_now()
      # head is resident too; oldest wins.
      head = %{account_id: account, enqueued_at: now}
      newer_resident = %{account_id: account, enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, newer_resident], "mac-01", tolerance_seconds: 30) ==
               {head, :head_resident}
    end
  end

  describe "select_candidate/3 with custom volumes" do
    setup do
      %{account: AccountsFixtures.account_fixture(), other: AccountsFixtures.account_fixture()}
    end

    # A custom volume a past job of the given workflow and job name attached.
    defp used_custom_volume(account, workflow_name, job_name, used_at \\ DateTime.utc_now()) do
      volume =
        Repo.insert!(%Volume{
          account_id: account.id,
          repository: "tuist/app",
          scope_id: "123",
          key: "gradle-#{System.unique_integer([:positive])}",
          platform: "linux",
          architecture: "amd64",
          uid: 1001
        })

      workflow_job_id = System.unique_integer([:positive])

      Repo.insert!(%WorkflowJob{
        workflow_job_id: workflow_job_id,
        workflow_run_id: 1,
        account_id: account.id,
        fleet_name: "test",
        status: "completed",
        repository: "tuist/app",
        workflow_name: workflow_name,
        job_name: job_name,
        enqueued_at: used_at
      })

      Repo.insert!(%Usage{
        volume_id: volume.id,
        generation: 1,
        workflow_job_id: workflow_job_id,
        workflow_run_id: 1,
        pod_name: "pod",
        pod_uid: "pod-#{workflow_job_id}",
        node_name: "linux-01",
        can_publish: true,
        inserted_at: DateTime.truncate(used_at, :second)
      })

      volume
    end

    defp stub_custom_residency(volumes) do
      labels =
        Map.new(volumes, fn volume ->
          {"tuist.dev/cache-volume-" <> String.slice(CacheVolumes.scope(volume), 0, 48), "true"}
        end)

      stub(K8sClient, :get_node, fn _ -> {:ok, %{"metadata" => %{"labels" => labels}}} end)
    end

    defp queued(account, workflow_name, job_name, enqueued_at) do
      %{
        account_id: account.id,
        repository: "tuist/app",
        workflow_name: workflow_name,
        job_name: job_name,
        enqueued_at: enqueued_at
      }
    end

    test "prefers a queued job whose recently used custom volume the node holds", %{account: account, other: other} do
      volume = used_custom_volume(account, "CI", "Build")
      stub_custom_residency([volume])
      now = DateTime.utc_now()
      head = queued(other, "CI", "Build", now)
      resident = queued(account, "CI", "Build", DateTime.add(now, 5, :second))

      assert VolumeAffinities.select_candidate([head, resident], "linux-01", tolerance_seconds: 30) ==
               {resident, :resident}
    end

    test "matches the workflow and job that used the volume", %{account: account} do
      volume = used_custom_volume(account, "CI", "Build")
      stub_custom_residency([volume])
      now = DateTime.utc_now()
      head = queued(account, "CI", "Lint", now)
      other_workflow = queued(account, "Release", "Build", DateTime.add(now, 5, :second))

      assert VolumeAffinities.select_candidate([head, other_workflow], "linux-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end

    test "only predicts from the last week of uses", %{account: account, other: other} do
      volume = used_custom_volume(account, "CI", "Build", DateTime.add(DateTime.utc_now(), -8, :day))
      stub_custom_residency([volume])
      now = DateTime.utc_now()
      head = queued(other, "CI", "Build", now)
      stale = queued(account, "CI", "Build", DateTime.add(now, 5, :second))

      assert VolumeAffinities.select_candidate([head, stale], "linux-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end

    test "a node that holds no custom volume gets no preference", %{account: account, other: other} do
      used_custom_volume(account, "CI", "Build")
      stub_custom_residency([])
      now = DateTime.utc_now()
      head = queued(other, "CI", "Build", now)
      candidate = queued(account, "CI", "Build", DateTime.add(now, 5, :second))

      assert VolumeAffinities.select_candidate([head, candidate], "linux-01", tolerance_seconds: 30) ==
               {head, :no_residency}
    end
  end

  # macOS custom volumes sized like the managed ones: `CI / Build` attaches the
  # 30 GB Xcode cache and the 20 GB module cache, `CI / Lint` only the module
  # cache. Each job in the history ran on `mac-01`.
  defp macos_volumes(account) do
    xcode = macos_volume(account, "tuist-xcode")
    module = macos_volume(account, "tuist-module")
    record_job(account, "CI", "Build", [xcode, module])
    record_job(account, "CI", "Lint", [module])
    %{xcode: xcode, module: module}
  end

  defp macos_volume(account, key) do
    Repo.insert!(%Volume{
      account_id: account.id,
      repository: "tuist/app",
      scope_id: "123",
      key: key,
      platform: "macos",
      architecture: "arm64",
      uid: 501
    })
  end

  # A job of `workflow_name / job_name`, with a use on `node_name` for each of
  # `volumes`.
  defp record_job(account, workflow_name, job_name, volumes, node_name \\ "mac-01") do
    workflow_job_id = System.unique_integer([:positive])

    Repo.insert!(%WorkflowJob{
      workflow_job_id: workflow_job_id,
      workflow_run_id: 1,
      account_id: account.id,
      fleet_name: "macos-ber1",
      status: "completed",
      repository: "tuist/app",
      workflow_name: workflow_name,
      job_name: job_name,
      enqueued_at: DateTime.utc_now()
    })

    for volume <- volumes do
      Repo.insert!(%Usage{
        volume_id: volume.id,
        generation: 1,
        workflow_job_id: workflow_job_id,
        workflow_run_id: 1,
        pod_name: "pod-#{workflow_job_id}",
        pod_uid: "pod-#{workflow_job_id}-#{volume.key}",
        node_name: node_name,
        can_publish: true,
        inserted_at: DateTime.utc_now(:second)
      })
    end

    workflow_job_id
  end

  # A runner on `node_name` running a job of `workflow_name / job_name` that has
  # attached `volumes` so far.
  defp occupy(node_name, account, workflow_name, job_name, volumes \\ [], ended_at \\ nil) do
    workflow_job_id = record_job(account, workflow_name, job_name, volumes, node_name)
    now = DateTime.utc_now()

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: workflow_job_id,
      fleet_name: "macos-ber1",
      pod_name: "pod-#{workflow_job_id}",
      node_name: node_name,
      runner_name: "",
      platform: :macos,
      vcpus: 6,
      memory_gb: 14,
      billing_multiplier: 10_000,
      repository: "tuist/app",
      workflow_name: workflow_name,
      started_at: now,
      ended_at: ended_at,
      inserted_at: DateTime.truncate(now, :second),
      updated_at: DateTime.truncate(now, :second)
    })
  end

  defp node_labels(volumes, capacity_gib) do
    labels = Map.new(volumes, &{"tuist.dev/cache-volume-" <> String.slice(CacheVolumes.scope(&1), 0, 48), "true"})

    if capacity_gib,
      do: Map.put(labels, "tuist.dev/cache-volume-capacity-gib", Integer.to_string(capacity_gib)),
      else: labels
  end

  defp queued_macos(account, workflow_name, job_name, enqueued_at) do
    %{
      account_id: account.id,
      repository: "tuist/app",
      workflow_name: workflow_name,
      job_name: job_name,
      enqueued_at: enqueued_at
    }
  end

  describe "select_candidate/3 with cache room" do
    setup do
      account = AccountsFixtures.account_fixture()
      volumes = macos_volumes(account)
      now = DateTime.utc_now()

      %{
        account: account,
        volumes: volumes,
        head: queued_macos(AccountsFixtures.account_fixture(), "CI", "Build", now),
        build: queued_macos(account, "CI", "Build", DateTime.add(now, 5, :second)),
        lint: queued_macos(account, "CI", "Lint", DateTime.add(now, 10, :second))
      }
    end

    defp stub_node(volumes, capacity_gib) do
      labels = node_labels(volumes, capacity_gib)
      stub(K8sClient, :get_node, fn "mac-01" -> {:ok, %{"metadata" => %{"labels" => labels}}} end)
    end

    test "keeps the preference while the node has room for the job's volumes", context do
      stub_node([context.volumes.xcode, context.volumes.module], 100)

      assert VolumeAffinities.select_candidate([context.head, context.build], "mac-01", tolerance_seconds: 30) ==
               {context.build, :resident}
    end

    test "drops the preference for a job whose volumes a runner dispatched to the node will need", context do
      # The runner was dispatched minutes before it attaches anything, so the
      # host has reserved nothing for it yet.
      stub_node([context.volumes.xcode, context.volumes.module], 90)
      occupy("mac-01", context.account, "CI", "Build")

      assert VolumeAffinities.select_candidate([context.head, context.build], "mac-01", tolerance_seconds: 30) ==
               {context.head, :no_room}
    end

    test "counts the volumes a running job allocated", context do
      stub_node([context.volumes.xcode, context.volumes.module], 90)
      occupy("mac-01", context.account, "Release", "Archive", [context.volumes.xcode, context.volumes.module])

      assert VolumeAffinities.select_candidate([context.head, context.build], "mac-01", tolerance_seconds: 30) ==
               {context.head, :no_room}
    end

    test "counts a volume a running job predicted and allocated once", context do
      stub_node([context.volumes.xcode, context.volumes.module], 110)
      occupy("mac-01", context.account, "CI", "Build", [context.volumes.xcode, context.volumes.module])

      assert VolumeAffinities.select_candidate([context.head, context.build], "mac-01", tolerance_seconds: 30) ==
               {context.build, :resident}
    end

    test "prefers a resident job that fits over an older one that does not", context do
      stub_node([context.volumes.xcode, context.volumes.module], 90)
      occupy("mac-01", context.account, "CI", "Build")

      assert VolumeAffinities.select_candidate([context.head, context.build, context.lint], "mac-01",
               tolerance_seconds: 30
             ) == {context.lint, :resident}
    end

    test "frees the room of a runner whose session ended", context do
      stub_node([context.volumes.xcode, context.volumes.module], 90)
      occupy("mac-01", context.account, "CI", "Build", [], DateTime.utc_now())

      assert VolumeAffinities.select_candidate([context.head, context.build], "mac-01", tolerance_seconds: 30) ==
               {context.build, :resident}
    end

    test "ignores runners on other nodes", context do
      stub_node([context.volumes.xcode, context.volumes.module], 90)
      occupy("mac-02", context.account, "CI", "Build")

      assert VolumeAffinities.select_candidate([context.head, context.build], "mac-01", tolerance_seconds: 30) ==
               {context.build, :resident}
    end

    test "keeps the preference on a node that advertises no capacity", context do
      stub_node([context.volumes.xcode, context.volumes.module], nil)
      occupy("mac-01", context.account, "CI", "Build")

      assert VolumeAffinities.select_candidate([context.head, context.build], "mac-01", tolerance_seconds: 30) ==
               {context.build, :resident}
    end
  end

  describe "preferred_nodes/3" do
    setup do
      account = AccountsFixtures.account_fixture()
      volumes = macos_volumes(account)

      stub(K8sClient, :get_runner_pool, fn _namespace, "macos-ber1" ->
        {:ok, %{"spec" => %{"fleetSelector" => "rack"}}}
      end)

      now = DateTime.utc_now()

      %{
        account: account,
        volumes: volumes,
        builds: for(seconds <- [0, 5, 10], do: queued_macos(account, "CI", "Build", DateTime.add(now, seconds, :second)))
      }
    end

    defp stub_fleet(nodes) do
      items = for {name, labels} <- nodes, do: %{"metadata" => %{"name" => name, "labels" => labels}}
      stub(K8sClient, :list_nodes, fn "tuist.dev/fleet=rack" -> {:ok, %{"items" => items}} end)
    end

    test "lists a holder once per job its cache disk fits", %{volumes: volumes, builds: builds} do
      held = [volumes.xcode, volumes.module]
      stub_fleet([{"mac-01", node_labels(held, 90)}, {"mac-02", node_labels([], 500)}])

      assert VolumeAffinities.preferred_nodes("macos-ber1", builds, 5) == ["mac-01"]
    end

    test "spreads jobs over holders, most room first", %{volumes: volumes, builds: builds} do
      held = [volumes.xcode, volumes.module]
      stub_fleet([{"mac-01", node_labels(held, 90)}, {"mac-03", node_labels(held, 100)}])

      assert VolumeAffinities.preferred_nodes("macos-ber1", builds, 5) == ["mac-03", "mac-01", "mac-03"]
    end

    test "prefers the holder of more of the job's volumes", %{volumes: volumes, builds: builds} do
      stub_fleet([
        {"mac-01", node_labels([volumes.module], 500)},
        {"mac-03", node_labels([volumes.xcode, volumes.module], 100)}
      ])

      assert VolumeAffinities.preferred_nodes("macos-ber1", builds, 1) == ["mac-03"]
    end

    test "subtracts the jobs whose runners occupy a holder", %{account: account, volumes: volumes, builds: builds} do
      held = [volumes.xcode, volumes.module]
      stub_fleet([{"mac-01", node_labels(held, 90)}])
      occupy("mac-01", account, "CI", "Build")

      assert VolumeAffinities.preferred_nodes("macos-ber1", builds, 5) == []
    end

    test "keeps every job on a holder that advertises no capacity", %{volumes: volumes, builds: builds} do
      stub_fleet([{"mac-01", node_labels([volumes.xcode, volumes.module], nil)}])

      assert VolumeAffinities.preferred_nodes("macos-ber1", builds, 2) == ["mac-01", "mac-01"]
    end

    test "prefers no Node for jobs with no recent volume", %{account: account, volumes: volumes} do
      stub_fleet([{"mac-01", node_labels([volumes.xcode, volumes.module], 100)}])

      assert VolumeAffinities.preferred_nodes(
               "macos-ber1",
               [queued_macos(account, "CI", "Deploy", DateTime.utc_now())],
               5
             ) ==
               []
    end

    test "prefers no Node when the pool cannot be read", %{builds: builds} do
      stub(K8sClient, :get_runner_pool, fn _namespace, _name -> {:error, :not_found} end)

      assert VolumeAffinities.preferred_nodes("macos-ber1", builds, 5) == []
    end
  end
end
