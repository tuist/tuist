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

    test "returns nil for no candidates" do
      assert VolumeAffinities.select_candidate([], "linux-01", tolerance_seconds: 30) == nil
    end

    test "gets no preference when the node is unreadable or unnamed", %{account: account, other: other} do
      used_custom_volume(account, "CI", "Build")
      stub(K8sClient, :get_node, fn _ -> {:error, :not_found} end)
      now = DateTime.utc_now()
      head = queued(other, "CI", "Build", now)
      candidate = queued(account, "CI", "Build", DateTime.add(now, 5, :second))

      assert VolumeAffinities.select_candidate([head, candidate], "linux-01", tolerance_seconds: 30) ==
               {head, :no_residency}

      assert VolumeAffinities.select_candidate([head, candidate], nil, tolerance_seconds: 30) ==
               {head, :no_residency}
    end

    test "reports a resident head without reordering", %{account: account} do
      volume = used_custom_volume(account, "CI", "Build")
      stub_custom_residency([volume])
      now = DateTime.utc_now()
      head = queued(account, "CI", "Build", DateTime.add(now, -60, :second))
      newer = queued(account, "CI", "Build", now)

      assert VolumeAffinities.select_candidate([head, newer], "linux-01", tolerance_seconds: 30) ==
               {head, :head_resident}
    end

    test "falls back to the head once the head has waited past the tolerance", %{account: account, other: other} do
      volume = used_custom_volume(account, "CI", "Build")
      stub_custom_residency([volume])
      now = DateTime.utc_now()
      head = queued(other, "CI", "Lint", DateTime.add(now, -60, :second))
      residents = for offset <- 1..20, do: queued(account, "CI", "Build", DateTime.add(now, -30 + offset, :second))

      assert VolumeAffinities.select_candidate([head | residents], "linux-01", tolerance_seconds: 30) ==
               {head, :head_overdue}
    end

    test "does not blame an overdue head with nothing resident queued on the starvation bound", %{
      account: account,
      other: other
    } do
      volume = used_custom_volume(account, "CI", "Build")
      stub_custom_residency([volume])
      head = queued(other, "CI", "Lint", DateTime.add(DateTime.utc_now(), -60, :second))

      assert VolumeAffinities.select_candidate([head], "linux-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end
  end

  # macOS custom volumes sized like the managed ones: `CI / Build` attaches the
  # 30 GB Xcode cache and the 20 GB module cache, `CI / Lint` only the module
  # cache. Each job in the history ran on `mac-01`. The default saved heads are
  # large enough that a host reserves each volume's whole capacity.
  defp macos_volumes(account, head_sizes \\ %{"tuist-xcode" => 25_000_000_000, "tuist-module" => 15_000_000_000}) do
    xcode = macos_volume(account, "tuist-xcode", head_sizes["tuist-xcode"])
    module = macos_volume(account, "tuist-module", head_sizes["tuist-module"])
    record_job(account, "CI", "Build", [xcode, module])
    record_job(account, "CI", "Lint", [module])
    %{xcode: xcode, module: module}
  end

  defp macos_volume(account, key, head_size_bytes) do
    volume =
      Repo.insert!(%Volume{
        account_id: account.id,
        repository: "tuist/app",
        scope_id: "123",
        key: key,
        platform: "macos",
        architecture: "arm64",
        uid: 501
      })

    head =
      Repo.insert!(%Usage{
        volume_id: volume.id,
        generation: 0,
        workflow_job_id: System.unique_integer([:positive]),
        workflow_run_id: 1,
        pod_name: "head",
        pod_uid: "head-#{key}",
        node_name: "mac-00",
        can_publish: true,
        status: "published",
        size_bytes: head_size_bytes,
        inserted_at: DateTime.utc_now(:second)
      })

    Repo.update!(Ecto.Changeset.change(volume, head_id: head.id))
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
        parent_id: volume.head_id,
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

    test "fits a job beside another whose volumes hold little" do
      account = AccountsFixtures.account_fixture()
      volumes = macos_volumes(account, %{"tuist-xcode" => 1_000_000_000, "tuist-module" => 500_000_000})
      now = DateTime.utc_now()
      head = queued_macos(AccountsFixtures.account_fixture(), "CI", "Build", now)
      build = queued_macos(account, "CI", "Build", DateTime.add(now, 5, :second))
      # A Build reserves 3 GB and 2.5 GB, not the 50 GB of the volumes' capacities.
      stub_node([volumes.xcode, volumes.module], 12)
      occupy("mac-01", account, "CI", "Build", [volumes.xcode, volumes.module])

      assert VolumeAffinities.select_candidate([head, build], "mac-01", tolerance_seconds: 30) == {build, :resident}
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
