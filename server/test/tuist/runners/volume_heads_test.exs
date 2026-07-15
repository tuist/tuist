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

  describe "bump_head/4" do
    test "establishes the HEAD at generation 1 on first promote" do
      account = account_fixture()

      assert :ok = VolumeHeads.bump_head(account.id, "mac-01", "digest-a")

      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id)
    end

    test "advances the generation and digest on each subsequent promote (last-writer-wins)" do
      account = account_fixture()

      VolumeHeads.bump_head(account.id, "mac-01", "digest-a")
      VolumeHeads.bump_head(account.id, "mac-02", "digest-b")

      assert %{generation: 2, tree_digest: "digest-b"} = VolumeHeads.get_head(account.id)
    end

    test "keeps one HEAD per account, independent across accounts" do
      a = account_fixture()
      b = account_fixture()

      VolumeHeads.bump_head(a.id, "mac-01", "a1")
      VolumeHeads.bump_head(a.id, "mac-01", "a2")
      VolumeHeads.bump_head(b.id, "mac-02", "b1")

      assert %{generation: 2, tree_digest: "a2"} = VolumeHeads.get_head(a.id)
      assert %{generation: 1, tree_digest: "b1"} = VolumeHeads.get_head(b.id)
    end

    test "no-ops on an empty digest" do
      account = account_fixture()
      assert :ok = VolumeHeads.bump_head(account.id, "mac-01", "")
      assert VolumeHeads.get_head(account.id) == nil
    end
  end
end
