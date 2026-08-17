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

  # Without this, a HEAD whose stored object does not reproduce its digest is
  # permanent: converging hosts verify the object and decline, so nobody holds that
  # generation, and every promote is then a cold one the fast-forward rejects. The
  # account can neither adopt the HEAD nor replace it — observed in production as
  # one account stuck cold on all nine hosts for days.
  describe "bump_head/6 retiring a HEAD reported unverifiable" do
    test "lets a cold promote take over the lineage it disproved" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "poisoned", 0)

      assert {:ok, 2} =
               VolumeHeads.bump_head(account.id, "mac-02", "digest-cold", 0, VolumeHeads.reserved_tuist_cache(),
                 unverifiable_digest: "poisoned"
               )

      # The generation ADVANCES rather than resetting to 1: hosts still holding an
      # older master compare against one monotonic counter, so a reset would leave
      # them refusing to install the newer master forever.
      assert %{generation: 2, tree_digest: "digest-cold"} = VolumeHeads.get_head(account.id)
    end

    test "keeps rejecting a cold promote that reports nothing" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      assert :conflict = VolumeHeads.bump_head(account.id, "mac-02", "digest-cold", 0)

      assert :conflict =
               VolumeHeads.bump_head(account.id, "mac-02", "digest-cold", 0, VolumeHeads.reserved_tuist_cache(),
                 unverifiable_digest: nil
               )

      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id)
    end

    test "retires only the digest the report names" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      # A report about a digest the HEAD has already moved off proves nothing about
      # the HEAD standing now, so the cold promote stays rejected. This is also the
      # race: another host advanced the HEAD between the download and this bump.
      assert :conflict =
               VolumeHeads.bump_head(account.id, "mac-02", "digest-cold", 0, VolumeHeads.reserved_tuist_cache(),
                 unverifiable_digest: "some-older-digest"
               )

      assert %{generation: 1, tree_digest: "digest-a"} = VolumeHeads.get_head(account.id)
    end

    test "lets a stale-warm host retire it too, not just a cold one" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)
      VolumeHeads.bump_head(account.id, "mac-02", "poisoned", 1)

      # A host holding generation 1 while a poisoned generation 2 stands is wedged
      # exactly like a cold one: it can never reach generation 2, because adopting
      # it is what the verification refuses, so its base stays 1 and its promote is
      # rejected forever. Once nobody holds the poisoned generation — the state
      # production was found in — gating the escape on the cold base would leave
      # every surviving stale-warm host stuck.
      assert {:ok, 3} =
               VolumeHeads.bump_head(account.id, "mac-03", "digest-stale-warm", 1, VolumeHeads.reserved_tuist_cache(),
                 unverifiable_digest: "poisoned"
               )

      assert %{generation: 3, tree_digest: "digest-stale-warm"} = VolumeHeads.get_head(account.id)
    end

    test "still rejects a stale warm base whose report names a superseded digest" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)
      VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1)

      # This is the guard that keeps the report from becoming a way around the
      # compare-and-swap: it retires only the HEAD standing right now. A report about
      # generation 1's digest says nothing about generation 2, so the stale promote
      # loses the fast-forward as before.
      assert :conflict =
               VolumeHeads.bump_head(account.id, "mac-03", "digest-stale", 1, VolumeHeads.reserved_tuist_cache(),
                 unverifiable_digest: "digest-a"
               )

      assert %{generation: 2, tree_digest: "digest-b"} = VolumeHeads.get_head(account.id)
    end

    test "leaves other accounts' heads alone" do
      a = account_fixture()
      b = account_fixture()
      VolumeHeads.bump_head(a.id, "mac-01", "shared-digest", 0)
      VolumeHeads.bump_head(b.id, "mac-02", "shared-digest", 0)

      assert {:ok, 2} =
               VolumeHeads.bump_head(a.id, "mac-03", "a-cold", 0, VolumeHeads.reserved_tuist_cache(),
                 unverifiable_digest: "shared-digest"
               )

      assert %{generation: 1, tree_digest: "shared-digest"} = VolumeHeads.get_head(b.id)
    end
  end

  describe "fast_forward_viable?/3" do
    test "agrees with bump_head on every base, so it only ever skips doomed work" do
      account = account_fixture()

      # No HEAD yet: only a cold base can win, exactly as establish_first_head.
      assert VolumeHeads.fast_forward_viable?(account.id, 0)
      refute VolumeHeads.fast_forward_viable?(account.id, 1)

      VolumeHeads.bump_head(account.id, "mac-01", "digest-a", 0)

      # HEAD at generation 1: a cold job and a job built on anything else are both
      # already lost; only the current generation can still fast-forward.
      refute VolumeHeads.fast_forward_viable?(account.id, 0)
      assert VolumeHeads.fast_forward_viable?(account.id, 1)
      refute VolumeHeads.fast_forward_viable?(account.id, 2)

      # And what it calls viable, bump_head accepts.
      assert {:ok, 2} = VolumeHeads.bump_head(account.id, "mac-02", "digest-b", 1)
      refute VolumeHeads.fast_forward_viable?(account.id, 1)
    end

    test "mirrors the retirement rule, so the pre-flight cannot 409 the promote that unwedges an account" do
      account = account_fixture()
      VolumeHeads.bump_head(account.id, "mac-01", "poisoned", 0)

      # The pre-flight runs BEFORE the upload. If it ignored the report it would
      # turn away every cold promote that could retire a poisoned HEAD, and the
      # bump — the actual authority — would never be reached.
      refute VolumeHeads.fast_forward_viable?(account.id, 0)

      assert VolumeHeads.fast_forward_viable?(account.id, 0, VolumeHeads.reserved_tuist_cache(),
               unverifiable_digest: "poisoned"
             )

      refute VolumeHeads.fast_forward_viable?(account.id, 0, VolumeHeads.reserved_tuist_cache(),
               unverifiable_digest: "another-digest"
             )

      # And for a stale-warm reporter, whose upload the pre-flight would otherwise
      # pre-empt on a base it can never advance.
      VolumeHeads.bump_head(account.id, "mac-02", "poisoned-2", 1)
      refute VolumeHeads.fast_forward_viable?(account.id, 1)

      assert VolumeHeads.fast_forward_viable?(account.id, 1, VolumeHeads.reserved_tuist_cache(),
               unverifiable_digest: "poisoned-2"
             )
    end

    test "reads as viable for anything it cannot evaluate" do
      account = account_fixture()

      # Fail-safe: a malformed base must never suppress a promote the
      # compare-and-swap would have accepted.
      assert VolumeHeads.fast_forward_viable?(account.id, "1")
      assert VolumeHeads.fast_forward_viable?(account.id, -1)
      assert VolumeHeads.fast_forward_viable?(nil, 0)
    end
  end
end
