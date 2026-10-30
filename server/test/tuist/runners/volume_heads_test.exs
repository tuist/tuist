defmodule Tuist.Runners.VolumeHeadsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.VolumeHead
  alias Tuist.Runners.VolumeHeads

  @volume "macos-" <> String.duplicate("a", 64)

  describe "valid_storage_volume_name?/1" do
    test "accepts custom volume storage names" do
      assert VolumeHeads.valid_storage_volume_name?("macos-" <> String.duplicate("a", 64))
      assert VolumeHeads.valid_storage_volume_name?("linux-" <> String.duplicate("0", 64))
    end

    test "rejects anything else" do
      refute VolumeHeads.valid_storage_volume_name?("tuist-cache")
      refute VolumeHeads.valid_storage_volume_name?("repo-eae044a4c27633ea")
      refute VolumeHeads.valid_storage_volume_name?("macos-" <> String.duplicate("a", 63))
      refute VolumeHeads.valid_storage_volume_name?("windows-" <> String.duplicate("a", 64))
      refute VolumeHeads.valid_storage_volume_name?(nil)
    end
  end

  describe "get_head/2" do
    test "returns nil for a volume that has never been published" do
      account = account_fixture()
      assert VolumeHeads.get_head(account.id, @volume) == nil
    end

    test "returns nil without an account id" do
      assert VolumeHeads.get_head(nil, @volume) == nil
    end
  end

  describe "bump_head/6" do
    test "establishes the HEAD at generation 1 on a first publish (base 0)" do
      account = account_fixture()

      assert {:ok, 1} = VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, @volume)

      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id, @volume)
    end

    test "carries the content digest on every path that writes the row, absence included" do
      account = account_fixture()

      assert {:ok, 1} =
               VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, @volume,
                 content_digest: String.duplicate("1", 64)
               )

      assert %{content_digest: content_digest} = VolumeHeads.get_head(account.id, @volume)
      assert content_digest == String.duplicate("1", 64)

      assert {:ok, 2} =
               VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, @volume,
                 content_digest: String.duplicate("2", 64)
               )

      assert %{content_digest: content_digest} = VolumeHeads.get_head(account.id, @volume)
      assert content_digest == String.duplicate("2", 64)

      assert {:ok, 3} = VolumeHeads.bump_head(account.id, "mac-03", "digest-c", 2, @volume)
      assert %{content_digest: nil} = VolumeHeads.get_head(account.id, @volume)
    end

    test "records the publishing host on every path that writes the row" do
      account = account_fixture()

      assert {:ok, 1} = VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, @volume)
      assert published_by(account.id) == "mac-01"

      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, @volume)
      assert published_by(account.id) == "mac-02"
    end

    test "rejects a cold publish (base 0) when a HEAD already exists" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, @volume)

      assert :conflict = VolumeHeads.bump_head(account.id, "mac-02", "digest-cold", 0, @volume)
      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id, @volume)
    end

    test "fast-forwards when the base is the current generation" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, @volume)

      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, @volume)
      assert %{generation: 2, tree_digest: "digest-b"} = VolumeHeads.get_head(account.id, @volume)
    end

    test "rejects a publish built on a stale base" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, @volume)
      VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, @volume)

      assert :conflict = VolumeHeads.bump_head(account.id, "mac-03", "digest-stale", 1, @volume)
      assert %{generation: 2, tree_digest: "digest-b"} = VolumeHeads.get_head(account.id, @volume)
    end

    test "keeps one HEAD per account and volume" do
      a = account_fixture()
      b = account_fixture()
      other_volume = "linux-" <> String.duplicate("b", 64)

      VolumeHeads.bump_head(a.id, "mac-01", "a1", 0, @volume)
      VolumeHeads.bump_head(a.id, "mac-01", "a2", 1, @volume)
      VolumeHeads.bump_head(a.id, "linux-01", "a-other", 0, other_volume)
      VolumeHeads.bump_head(b.id, "mac-02", "b1", 0, @volume)

      assert %{generation: 2, tree_digest: "a2"} = VolumeHeads.get_head(a.id, @volume)
      assert %{generation: 1, tree_digest: "a-other"} = VolumeHeads.get_head(a.id, other_volume)
      assert %{generation: 1, tree_digest: "b1"} = VolumeHeads.get_head(b.id, @volume)
    end

    test "rejects an empty digest" do
      account = account_fixture()
      assert :conflict = VolumeHeads.bump_head(account.id, "mac-01", "", 0, @volume)
      assert VolumeHeads.get_head(account.id, @volume) == nil
    end
  end

  describe "fast_forward_viable?/3" do
    test "agrees with bump_head on every base, so it only ever skips doomed work" do
      account = account_fixture()

      assert VolumeHeads.fast_forward_viable?(account.id, 0, @volume)
      refute VolumeHeads.fast_forward_viable?(account.id, 1, @volume)

      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0, @volume)

      refute VolumeHeads.fast_forward_viable?(account.id, 0, @volume)
      assert VolumeHeads.fast_forward_viable?(account.id, 1, @volume)
      refute VolumeHeads.fast_forward_viable?(account.id, 2, @volume)

      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1, @volume)
      refute VolumeHeads.fast_forward_viable?(account.id, 1, @volume)
    end

    test "reads as viable for anything it cannot evaluate" do
      account = account_fixture()

      assert VolumeHeads.fast_forward_viable?(account.id, "1", @volume)
      assert VolumeHeads.fast_forward_viable?(account.id, -1, @volume)
      assert VolumeHeads.fast_forward_viable?(nil, 0, @volume)
    end
  end

  defp published_by(account_id) do
    Repo.get_by!(VolumeHead, account_id: account_id, volume_name: @volume).node_name
  end
end
