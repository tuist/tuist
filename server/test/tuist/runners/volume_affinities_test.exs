defmodule Tuist.Runners.VolumeAffinitiesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.VolumeAffinities

  describe "record/3" do
    test "upserts one row per (node, account, volume) and bumps last_run_at" do
      account = account_fixture()

      assert :ok = VolumeAffinities.record("mac-01", account.id)
      assert MapSet.member?(VolumeAffinities.affine_account_ids("mac-01"), account.id)

      # A second claim on the same host upserts (no duplicate row); the
      # account stays affine.
      assert :ok = VolumeAffinities.record("mac-01", account.id)
      assert VolumeAffinities.affine_account_ids("mac-01") == MapSet.new([account.id])
    end

    test "no-ops without node identity (nil/empty node)" do
      account = account_fixture()
      assert :ok = VolumeAffinities.record(nil, account.id)
      assert :ok = VolumeAffinities.record("", account.id)
      assert VolumeAffinities.affine_account_ids("mac-01") == MapSet.new()
    end
  end

  describe "affine_account_ids/2" do
    test "scopes to the node and volume" do
      a = account_fixture()
      b = account_fixture()
      VolumeAffinities.record("mac-01", a.id)
      VolumeAffinities.record("mac-02", b.id)

      assert VolumeAffinities.affine_account_ids("mac-01") == MapSet.new([a.id])
      assert VolumeAffinities.affine_account_ids("mac-02") == MapSet.new([b.id])
      assert VolumeAffinities.affine_account_ids("mac-03") == MapSet.new()
    end
  end

  describe "select_candidate/4" do
    setup do
      account = account_fixture()
      other = account_fixture()
      %{account: account, other: other}
    end

    test "returns nil for no candidates" do
      assert VolumeAffinities.select_candidate([], "mac-01", 30) == nil
    end

    test "returns the head when the node has no affinity", %{account: account, other: other} do
      now = DateTime.utc_now()
      head = %{account_id: other.id, enqueued_at: now}
      affine = %{account_id: account.id, enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, affine], "mac-01", 30) == head
    end

    test "prefers the affine account's job within the tolerance", %{account: account, other: other} do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      head = %{account_id: other.id, enqueued_at: now}
      affine = %{account_id: account.id, enqueued_at: DateTime.add(now, 10, :second)}

      # 10s newer than head, within a 30s tolerance -> affinity wins.
      assert VolumeAffinities.select_candidate([head, affine], "mac-01", 30) == affine
    end

    test "falls back to the head when the affine job is past the tolerance", %{account: account, other: other} do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      head = %{account_id: other.id, enqueued_at: now}
      affine = %{account_id: account.id, enqueued_at: DateTime.add(now, 60, :second)}

      # 60s newer than head, past a 30s tolerance -> head wins (affinity
      # never delays a job past the tolerance).
      assert VolumeAffinities.select_candidate([head, affine], "mac-01", 30) == head
    end

    test "returns the oldest affine candidate when several are affine", %{account: account} do
      VolumeAffinities.record("mac-01", account.id)
      now = DateTime.utc_now()
      # head is affine too; oldest wins.
      head = %{account_id: account.id, enqueued_at: now}
      newer_affine = %{account_id: account.id, enqueued_at: DateTime.add(now, 5, :second)}

      assert VolumeAffinities.select_candidate([head, newer_affine], "mac-01", 30) == head
    end
  end

  describe "prune/1" do
    test "deletes rows older than the retention window" do
      account = account_fixture()
      VolumeAffinities.record("mac-01", account.id)

      # Nothing to prune yet.
      assert VolumeAffinities.prune() == 0
      assert MapSet.member?(VolumeAffinities.affine_account_ids("mac-01"), account.id)

      # A negative retention pushes the cutoff into the future, so the
      # just-written row falls outside the window and is pruned.
      assert VolumeAffinities.prune(-1) == 1
      assert VolumeAffinities.affine_account_ids("mac-01") == MapSet.new()
    end
  end
end
