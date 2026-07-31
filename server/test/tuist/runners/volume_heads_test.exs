defmodule Tuist.Runners.VolumeHeadsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.VolumeHeads

  describe "get_head/2" do
    test "returns nil for an account that has never promoted a volume" do
      account = account_fixture()
      assert VolumeHeads.get_head(account.id) == nil
    end

    test "returns nil without an account id" do
      assert VolumeHeads.get_head(nil) == nil
    end
  end

  describe "bump_head/5" do
    test "establishes the HEAD at generation 1 on a first promote (base 0)" do
      account = account_fixture()

      assert {:ok, 1} = VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id)
    end

    test "rejects a cold promote (base 0) when a HEAD already exists" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      # A second cold job built on nothing while the fleet has a HEAD: rejected,
      # so it cannot clobber the existing lineage with its poorer set.
      assert :conflict = VolumeHeads.bump_head(account.id, "mac-02", "digest-cold", 0)
      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id)
    end

    test "fast-forwards when the base is the current generation" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1)
      assert %{generation: 2, tree_digest: "digest-b"} = VolumeHeads.get_head(account.id)
    end

    test "rejects a warm promote built on a stale base" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)
      VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1)

      # A job that materialized from generation 1 promotes after another host
      # already advanced the HEAD to generation 2: rejected (no fast-forward),
      # HEAD untouched.
      assert :conflict = VolumeHeads.bump_head(account.id, "mac-03", "digest-stale", 1)
      assert %{generation: 2, tree_digest: "digest-b"} = VolumeHeads.get_head(account.id)
    end

    test "keeps one HEAD per account, independent across accounts" do
      a = account_fixture()
      b = account_fixture()

      VolumeHeads.bump_head(a.id, "mac-01", "a1", 0)
      VolumeHeads.bump_head(a.id, "mac-01", "a2", 1)
      VolumeHeads.bump_head(b.id, "mac-02", "b1", 0)

      assert %{generation: 2, tree_digest: "a2"} = VolumeHeads.get_head(a.id)
      assert %{generation: 1, tree_digest: "b1"} = VolumeHeads.get_head(b.id)
    end

    test "rejects an empty digest" do
      account = account_fixture()
      assert :conflict = VolumeHeads.bump_head(account.id, "mac-01", "", 0)
      assert VolumeHeads.get_head(account.id) == nil
    end
  end

  describe "bump_head/5 compilation-cache guard" do
    test "refuses a promote that would drop the HEAD's compilation cache" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, cas_present: true)

      # A host that writes no compilation cache promotes on a perfectly current
      # base. The fast-forward would accept it — it only orders by generation —
      # and every other host would then converge to a warm set with no CAS.
      assert :cas_regression = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1)

      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id)
      assert cas_present?(account.id)
    end

    test "accepts a promote that keeps the compilation cache" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, cas_present: true)

      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, cas_present: true)
      assert cas_present?(account.id)
    end

    test "accepts a CAS-less promote when the HEAD has no compilation cache either" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1)
      refute cas_present?(account.id)
    end

    test "accepts a promote that adds a compilation cache" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, cas_present: true)
      assert cas_present?(account.id)
    end

    test "accepts an intentional reclaim so an operator's disable can propagate" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, cas_present: true)

      # Without this the disable could never reach the HEAD, and every master
      # would keep cloning dead CAS bytes forever.
      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, cas_disabled: true)

      refute cas_present?(account.id)
      # And once the HEAD is CAS-less, ordinary promotes flow again.
      assert {:ok, 3} = VolumeHeads.bump_head(account.id, "mac-03", "digest-c", 2)
    end

    test "reports a stale base as a conflict even when the promote drops the CAS" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, cas_present: true)
      VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, cas_present: true)

      # Both guards would reject this one. It is contention first: the runner
      # discards either way, but the outcome drives which signal fires.
      assert :conflict = VolumeHeads.bump_head(account.id, "mac-03", "digest-stale", 1)
    end
  end

  defp cas_present?(account_id) do
    Tuist.Repo.get_by!(Tuist.Runners.VolumeHead,
      account_id: account_id,
      volume_name: VolumeHeads.reserved_tuist_cache()
    ).cas_present
  end
end
