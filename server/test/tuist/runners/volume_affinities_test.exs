defmodule Tuist.Runners.VolumeAffinitiesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.VolumeAffinities

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
end
