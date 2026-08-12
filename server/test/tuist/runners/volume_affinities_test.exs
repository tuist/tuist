defmodule Tuist.Runners.VolumeAffinitiesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.VolumeAffinities
  alias Tuist.Runners.VolumeAffinity

  # Records `account` on `node` as having run `seconds_ago` seconds ago, so a
  # test can lay out an explicit recency order (the inverse of the host's LRU
  # eviction order) instead of relying on insert timing.
  defp record_at(node, account, seconds_ago) do
    :ok = VolumeAffinities.record(node, account.id)

    last_run_at =
      DateTime.utc_now()
      |> DateTime.add(-seconds_ago, :second)
      |> DateTime.truncate(:second)

    {1, _} =
      Repo.update_all(
        from(v in VolumeAffinity, where: v.node_name == ^node and v.account_id == ^account.id),
        set: [last_run_at: last_run_at]
      )

    :ok
  end

  describe "record/3" do
    test "upserts one row per (node, account, volume) and bumps last_run_at" do
      account = account_fixture()

      assert :ok = VolumeAffinities.record("mac-01", account.id)
      assert MapSet.member?(VolumeAffinities.resident_account_ids("mac-01"), account.id)

      # A second claim on the same host upserts (no duplicate row); the
      # account stays resident.
      assert :ok = VolumeAffinities.record("mac-01", account.id)
      assert VolumeAffinities.resident_account_ids("mac-01") == MapSet.new([account.id])
    end

    test "no-ops without node identity (nil/empty node)" do
      account = account_fixture()
      assert :ok = VolumeAffinities.record(nil, account.id)
      assert :ok = VolumeAffinities.record("", account.id)
      assert VolumeAffinities.resident_account_ids("mac-01") == MapSet.new()
    end
  end

  describe "resident_account_ids/3" do
    test "scopes to the node and volume" do
      a = account_fixture()
      b = account_fixture()
      VolumeAffinities.record("mac-01", a.id)
      VolumeAffinities.record("mac-02", b.id)

      assert VolumeAffinities.resident_account_ids("mac-01") == MapSet.new([a.id])
      assert VolumeAffinities.resident_account_ids("mac-02") == MapSet.new([b.id])
      assert VolumeAffinities.resident_account_ids("mac-03") == MapSet.new()
    end

    test "keeps only the most recent `limit` accounts, mirroring host LRU eviction" do
      newest = account_fixture()
      middle = account_fixture()
      oldest = account_fixture()

      record_at("mac-01", oldest, 300)
      record_at("mac-01", middle, 200)
      record_at("mac-01", newest, 100)

      # The host holds 2 masters, so the third-most-recent account has been
      # evicted there and must not be preferred. This is the whole fix: left
      # unbounded, the set contains every account that ever ran on the node,
      # which makes the preference indistinguishable from no preference.
      assert VolumeAffinities.resident_account_ids("mac-01", 2) == MapSet.new([newest.id, middle.id])
      assert VolumeAffinities.resident_account_ids("mac-01", 1) == MapSet.new([newest.id])
      assert VolumeAffinities.resident_account_ids("mac-01", 3) == MapSet.new([newest.id, middle.id, oldest.id])
    end

    test "a non-positive limit disables the preference rather than unbounding it" do
      account = account_fixture()
      VolumeAffinities.record("mac-01", account.id)

      assert VolumeAffinities.resident_account_ids("mac-01", 0) == MapSet.new()
      assert VolumeAffinities.resident_account_ids("mac-01", -1) == MapSet.new()
    end
  end

  describe "select_candidate/3" do
    setup do
      %{account: account_fixture(), other: account_fixture()}
    end

    test "returns nil for no candidates" do
      assert VolumeAffinities.select_candidate([], "mac-01", tolerance_seconds: 30) == nil
    end

    test "returns the head when the node holds no masters", %{account: account, other: other} do
      now = DateTime.utc_now()
      head = %{account_id: other.id, enqueued_at: now}
      resident = %{account_id: account.id, enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {head, :no_residency}
    end

    test "prefers a resident account's job while the head is within the tolerance", %{
      account: account,
      other: other
    } do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      head = %{account_id: other.id, enqueued_at: now}
      resident = %{account_id: account.id, enqueued_at: DateTime.add(now, 10, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {resident, :resident}
    end

    test "does not prefer an account the node has evicted", %{account: account, other: other} do
      evicted = account_fixture()

      record_at("mac-01", evicted, 300)
      record_at("mac-01", account, 200)
      record_at("mac-01", other, 100)

      now = DateTime.utc_now()
      head = %{account_id: account.id, enqueued_at: now}
      evicted_candidate = %{account_id: evicted.id, enqueued_at: DateTime.add(now, 5, :second)}

      # `evicted` ran here least recently, so at a bound of 2 its master is
      # gone; the queue must not be reordered for it. The head's own account is
      # still resident, so this dispatch is warm anyway.
      assert VolumeAffinities.select_candidate([head, evicted_candidate], "mac-01",
               tolerance_seconds: 30,
               resident_limit: 2
             ) == {head, :head_resident}
    end

    test "reports when nothing queued matches the node's masters", %{account: account, other: other} do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      head = %{account_id: other.id, enqueued_at: now}

      assert VolumeAffinities.select_candidate([head], "mac-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end

    test "affinity wins regardless of the enqueue gap to the head, as long as the head is fresh",
         %{account: account, other: other} do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      # Far newer than the head, but the head itself has waited ~0s, so the
      # bound is on head age (from now), not the candidate-vs-head gap.
      head = %{account_id: other.id, enqueued_at: now}
      resident = %{account_id: account.id, enqueued_at: DateTime.add(now, 300, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {resident, :resident}
    end

    test "falls back to the head once the head has waited past the tolerance", %{
      account: account,
      other: other
    } do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      # Head was enqueued 60s ago, exceeding the 30s tolerance: it must be
      # handed out now even though a resident candidate exists. This is the
      # burst-starvation bound — a run of resident jobs can't pass the head
      # over indefinitely, because the head's own age caps the delay.
      head = %{account_id: other.id, enqueued_at: DateTime.add(now, -60, :second)}
      resident = %{account_id: account.id, enqueued_at: DateTime.add(now, -50, :second)}

      assert VolumeAffinities.select_candidate([head, resident], "mac-01", tolerance_seconds: 30) ==
               {head, :head_overdue}
    end

    test "an overdue head with nothing resident queued is not blamed on the starvation bound", %{
      account: account,
      other: other
    } do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      # Overdue, but there was no resident candidate to give up, so the bound
      # cost nothing. Reporting :head_overdue here would overstate what the
      # tolerance is costing and push it to be raised for no gain.
      head = %{account_id: other.id, enqueued_at: DateTime.add(now, -60, :second)}

      assert VolumeAffinities.select_candidate([head], "mac-01", tolerance_seconds: 30) ==
               {head, :no_resident_candidate}
    end

    test "the starvation bound holds no matter how many resident jobs are queued ahead of it", %{
      account: account,
      other: other
    } do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      head = %{account_id: other.id, enqueued_at: DateTime.add(now, -31, :second)}

      residents =
        for offset <- 1..20, do: %{account_id: account.id, enqueued_at: DateTime.add(now, -30 + offset, :second)}

      assert {^head, :head_overdue} =
               VolumeAffinities.select_candidate([head | residents], "mac-01", tolerance_seconds: 30)
    end

    test "returns the oldest resident candidate when several are resident", %{account: account} do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      # head is resident too; oldest wins.
      head = %{account_id: account.id, enqueued_at: now}
      newer_resident = %{account_id: account.id, enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, newer_resident], "mac-01", tolerance_seconds: 30) ==
               {head, :head_resident}
    end
  end

  describe "prune/1" do
    test "deletes rows older than the retention window" do
      account = account_fixture()
      VolumeAffinities.record("mac-01", account.id)

      # Nothing to prune yet.
      assert VolumeAffinities.prune() == 0
      assert MapSet.member?(VolumeAffinities.resident_account_ids("mac-01"), account.id)

      # A negative retention pushes the cutoff into the future, so the
      # just-written row falls outside the window and is pruned.
      assert VolumeAffinities.prune(-1) == 1
      assert VolumeAffinities.resident_account_ids("mac-01") == MapSet.new()
    end
  end
end
