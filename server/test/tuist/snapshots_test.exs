defmodule Tuist.SnapshotsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Repo
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Build
  alias Tuist.Snapshots.Diff
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @a String.duplicate("a", 40)
  @b String.duplicate("b", 40)
  @c String.duplicate("c", 40)
  @d String.duplicate("d", 40)

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

    # An in-memory object store, so comparisons read the bytes their builds uploaded.
    store = :ets.new(:snapshot_objects, [:public])
    stub(Storage, :put_object, fn key, content, _actor -> :ets.insert(store, {key, content}) && :ok end)

    stub(Storage, :get_object_as_string, fn key, _actor ->
      case :ets.lookup(store, key) do
        [{_, content}] -> content
        [] -> nil
      end
    end)

    stub(Storage, :object_exists?, fn key, _actor -> :ets.member(store, key) end)

    %{project: project, user: user}
  end

  # A white image with a blue square at `x`, so two images differ in exactly the squares' pixels.
  defp png(x, width \\ 100, height \\ 80) do
    {:ok, image} = Image.new(width, height, color: [255, 255, 255])
    {:ok, square} = Image.new(10, 10, color: [0, 0, 255])
    {:ok, image} = Image.compose(image, square, x: x, y: 5)
    {:ok, image} = Image.flatten(image)
    {:ok, binary} = Image.write(image, :memory, suffix: ".png")
    binary
  end

  defp hash(binary), do: Base.encode16(:crypto.hash(:sha256, binary), case: :lower)

  defp processed_build(project, attrs, images) do
    entries =
      Enum.map(images, fn image ->
        {name, binary, metadata} =
          case image do
            {name, binary} -> {name, binary, %{}}
            {name, binary, metadata} -> {name, binary, metadata}
          end

        Storage.put_object(Snapshots.blob_key(project, hash(binary)), binary, project.account)
        Map.merge(%{name: name, content_hash: hash(binary), width: 100, height: 80}, metadata)
      end)

    {:ok, build, _missing} = Snapshots.create_build(project, Map.put_new(attrs, :set_name, "phone"), entries)
    {:ok, build} = Snapshots.complete_build(project, build)
    {:ok, build} = Snapshots.process_build(build)
    build
  end

  describe "create_build/3" do
    test "asks only for the images no completed build of the project uploaded", %{project: project} do
      stored = png(5)
      new = png(50)
      processed_build(project, %{git_branch: "main"}, [{"a.png", stored}])

      {:ok, _abandoned, _} =
        Snapshots.create_build(project, %{set_name: "phone"}, [%{name: "b.png", content_hash: hash(new)}])

      {:ok, _build, missing} =
        Snapshots.create_build(project, %{set_name: "phone"}, [
          %{name: "a.png", content_hash: hash(stored)},
          %{name: "b.png", content_hash: hash(new)}
        ])

      # The abandoned build never completed, so its image may never have been put.
      assert missing == [hash(new)]
    end

    test "rejects duplicate names and paths escaping the directory", %{project: project} do
      image = %{name: "a.png", content_hash: hash(png(5))}

      assert {:error, :duplicate_image_names} = Snapshots.create_build(project, %{set_name: "phone"}, [image, image])

      assert {:error, :invalid_image_name} =
               Snapshots.create_build(project, %{set_name: "phone"}, [%{image | name: "../a.png"}])
    end

    test "won't complete a build whose images were not uploaded", %{project: project} do
      binary = png(5)

      {:ok, build, _} =
        Snapshots.create_build(project, %{set_name: "phone"}, [%{name: "a.png", content_hash: hash(binary)}])

      assert {:error, {:missing_images, [missing]}} = Snapshots.complete_build(project, build)
      assert missing == hash(binary)
    end
  end

  describe "process_build/1" do
    test "classifies every image against the baseline", %{project: project} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [
        {"same.png", png(5)},
        {"moved.png", png(5)},
        {"resized.png", png(5)},
        {"gone.png", png(5), %{display_name: "Gone", group: "Cards", tags: %{"ui_mode" => "dark"}}}
      ])

      build =
        processed_build(project, %{git_branch: "feature", merge_base_sha: @a}, [
          {"same.png", png(5)},
          {"moved.png", png(50)},
          {"resized.png", png(5, 120, 80)},
          {"new.png", png(15)}
        ])

      images = Map.new(Snapshots.list_images(build), &{&1.name, &1})

      assert images["same.png"].status == "unchanged"
      assert images["new.png"].status == "added"
      assert images["gone.png"].status == "removed"
      assert images["gone.png"].baseline_content_hash == hash(png(5))
      assert {images["gone.png"].group, images["gone.png"].tags} == {"Cards", %{"ui_mode" => "dark"}}

      # The square moved: its old and new 10×10 positions differ, 200 of 8,000 pixels.
      assert images["moved.png"].status == "changed"
      assert_in_delta images["moved.png"].diff_ratio, 0.025, 1.0e-9
      assert {:ok, _diff} = Snapshots.image_binary(project, images["moved.png"], :diff)

      # Only the 20 columns the image grew by differ: 1,600 of the 120×80 canvas' 9,600 pixels.
      assert images["resized.png"].status == "changed"
      assert_in_delta images["resized.png"].diff_ratio, 1600 / 9600, 1.0e-9
      assert {:ok, diff} = Snapshots.image_binary(project, images["resized.png"], :diff)
      assert {:ok, {120, 80}} = Diff.dimensions(diff)

      assert %Build{changed_count: 2, added_count: 1, removed_count: 1, unchanged_count: 1} = build
      assert Snapshots.status(build, project) == "needs_review"
    end

    test "treats different bytes with the same pixels as unchanged", %{project: project} do
      {:ok, image} = Image.from_binary(png(5))
      {:ok, rgba} = Image.add_alpha(image, 255)
      {:ok, reencoded} = Image.write(rgba, :memory, suffix: ".png")
      refute hash(reencoded) == hash(png(5))

      processed_build(project, %{git_branch: "main"}, [{"a.png", png(5)}])
      build = processed_build(project, %{git_branch: "feature"}, [{"a.png", reencoded}])

      assert [%{status: "unchanged"}] = Snapshots.list_images(build)
      assert Snapshots.status(build, project) == "passed"
    end
  end

  describe "resolve_baseline/1" do
    test "prefers the build at the merge base over the default branch's newest", %{project: project} do
      at_merge_base = processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      _newer_main = processed_build(project, %{git_branch: "main", git_commit_sha: @b}, [{"a.png", png(50)}])

      build = processed_build(project, %{git_branch: "feature", merge_base_sha: @a}, [{"a.png", png(5)}])

      assert build.baseline_build_id == at_merge_base.id
      assert Snapshots.status(build, project) == "passed"
    end

    test "falls back to the default branch's newest build without a merge base", %{project: project} do
      _older = processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      newest = processed_build(project, %{git_branch: "main", git_commit_sha: @b}, [{"a.png", png(50)}])

      build = processed_build(project, %{git_branch: "feature"}, [{"a.png", png(50)}])

      assert build.baseline_build_id == newest.id
    end

    test "only approved builds of other branches are baselines", %{project: project, user: user} do
      main = processed_build(project, %{git_branch: "main"}, [{"a.png", png(5)}])
      feature = processed_build(project, %{git_branch: "feature", git_commit_sha: @b}, [{"a.png", png(50)}])

      unapproved_child = processed_build(project, %{git_branch: "feature-2", merge_base_sha: @b}, [{"a.png", png(50)}])
      assert unapproved_child.baseline_build_id == main.id

      {:ok, feature} = Snapshots.approve_build(feature, user.account)
      assert Snapshots.status(feature, project) == "approved"

      approved_child = processed_build(project, %{git_branch: "feature-2", merge_base_sha: @b}, [{"a.png", png(50)}])
      assert approved_child.baseline_build_id == feature.id
    end

    test "compares only within the build's set", %{project: project} do
      processed_build(project, %{set_name: "tablet", git_branch: "main"}, [{"a.png", png(5)}])
      build = processed_build(project, %{set_name: "phone", git_branch: "main"}, [{"a.png", png(50)}])

      assert is_nil(build.baseline_build_id)
      assert [%{status: "added"}] = Snapshots.list_images(build)
      assert Repo.get!(Build, build.id).added_count == 1
    end
  end

  describe "checkout_baseline/2" do
    test "is the build a build uploaded from the checkout would be compared with", %{project: project} do
      at_merge_base = processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      _newer_main = processed_build(project, %{git_branch: "main", git_commit_sha: @b}, [{"a.png", png(50)}])

      assert Snapshots.checkout_baseline(project, %{set: "phone", git_commit_sha: @c, merge_base_sha: @a}).id ==
               at_merge_base.id

      assert is_nil(Snapshots.checkout_baseline(project, %{set: "tablet", git_commit_sha: @c}))
    end
  end

  describe "diff thresholds" do
    test "an image whose difference is within its threshold is unchanged", %{project: project} do
      processed_build(project, %{git_branch: "main"}, [{"loose.png", png(5)}, {"strict.png", png(5)}])

      # The moved square changes 200 of 8,000 pixels: 2.5%.
      build =
        processed_build(project, %{git_branch: "feature"}, [
          {"loose.png", png(50), %{diff_threshold: 0.03, group: "Checkout", tags: %{"theme" => "dark"}}},
          {"strict.png", png(50), %{diff_threshold: 0.02}}
        ])

      images = Map.new(Snapshots.list_images(build), &{&1.name, &1})

      assert %{status: "unchanged", group: "Checkout", tags: %{"theme" => "dark"}} = images["loose.png"]
      assert_in_delta images["loose.png"].diff_ratio, 0.025, 1.0e-9
      assert images["strict.png"].status == "changed"
      assert %Build{changed_count: 1, unchanged_count: 1} = build
    end

    test "rejects thresholds outside 0 to 1", %{project: project} do
      assert {:error, :invalid_image_metadata} =
               Snapshots.create_build(project, %{set_name: "phone"}, [
                 %{name: "a.png", content_hash: hash(png(5)), diff_threshold: 1.5}
               ])
    end
  end

  describe "inherited approvals" do
    test "a later build with the same changes on the branch is approved", %{project: project, user: user} do
      processed_build(project, %{git_branch: "main"}, [{"a.png", png(5)}, {"b.png", png(5)}])
      first = processed_build(project, %{git_branch: "feature"}, [{"a.png", png(50)}, {"b.png", png(5)}])
      {:ok, first} = Snapshots.approve_build(first, user.account)

      # A new commit that touches nothing the reviewer saw, plus a new image.
      same =
        processed_build(project, %{git_branch: "feature"}, [{"a.png", png(50)}, {"b.png", png(5)}, {"c.png", png(5)}])

      assert Snapshots.status(same, project) == "approved"
      assert same.approved_from_build_id == first.id
      assert same.approved_by_account_id == user.account.id

      # The approved image changed again: it needs another look.
      again = processed_build(project, %{git_branch: "feature"}, [{"a.png", png(60)}, {"b.png", png(5)}])
      assert Snapshots.status(again, project) == "needs_review"

      # Another branch with the same changes reviews them itself.
      other = processed_build(project, %{git_branch: "other"}, [{"a.png", png(50)}, {"b.png", png(5)}])
      assert Snapshots.status(other, project) == "needs_review"
    end
  end

  describe "renamed images" do
    test "pairs each removed image with one added image of the same content", %{project: project} do
      processed_build(project, %{git_branch: "main"}, [
        {"old.png", png(5)},
        {"twin-1.png", png(30)},
        {"twin-2.png", png(30)},
        {"keep.png", png(70)}
      ])

      build =
        processed_build(project, %{git_branch: "feature"}, [
          {"new.png", png(5)},
          {"twin.png", png(30)},
          {"keep.png", png(70)},
          # Same content as an image that is still there: a copy, not a rename.
          {"copy.png", png(70)},
          {"fresh.png", png(40)}
        ])

      images = Map.new(Snapshots.list_images(build), &{&1.name, &1})

      assert %{status: "renamed", renamed_from: "old.png"} = images["new.png"]
      assert %{status: "renamed", renamed_from: "twin-1.png"} = images["twin.png"]
      assert images["twin-2.png"].status == "removed"
      assert images["copy.png"].status == "added"
      assert images["fresh.png"].status == "added"
      refute Map.has_key?(images, "old.png")

      assert %Build{renamed_count: 2, removed_count: 1, added_count: 2, unchanged_count: 1, changed_count: 0} = build
    end

    test "a rename alone needs no review", %{project: project} do
      processed_build(project, %{git_branch: "main"}, [{"old.png", png(5)}])
      build = processed_build(project, %{git_branch: "feature"}, [{"new.png", png(5)}])

      assert Snapshots.status(build, project) == "passed"
    end
  end

  describe "selective runs" do
    test "images the run didn't render are carried over from the baseline", %{project: project} do
      processed_build(project, %{git_branch: "main"}, [
        {"a.png", png(5)},
        {"b.png", png(10)},
        {"c.png", png(20)},
        {"d.png", png(30)}
      ])

      # Rendered only a.png. d.png is no longer in the suite, and z.png never had a baseline.
      selective =
        processed_build(
          project,
          %{git_branch: "main", all_image_names: ["a.png", "b.png", "c.png", "z.png"]},
          [{"a.png", png(5)}]
        )

      images = Map.new(Snapshots.list_images(selective), &{&1.name, &1})

      assert %{status: "skipped", content_hash: b_hash, baseline_content_hash: b_hash} = images["b.png"]
      assert b_hash == hash(png(10))
      assert images["c.png"].status == "skipped"
      assert images["d.png"].status == "removed"
      refute Map.has_key?(images, "z.png")
      assert %Build{skipped_count: 2, removed_count: 1, unchanged_count: 1} = selective

      # The selective build is a complete baseline: the skipped images are still there.
      full =
        processed_build(project, %{git_branch: "feature"}, [{"a.png", png(5)}, {"b.png", png(10)}, {"c.png", png(20)}])

      assert full.baseline_build_id == selective.id
      assert %Build{unchanged_count: 3, added_count: 0} = full
    end

    test "a build marked selective skips every baseline image it didn't upload", %{project: project} do
      processed_build(project, %{git_branch: "main"}, [{"a.png", png(5)}, {"b.png", png(10)}])
      build = processed_build(project, %{git_branch: "feature", selective: true}, [{"a.png", png(5)}])

      assert %Build{skipped_count: 1, removed_count: 0} = build
      assert Snapshots.status(build, project) == "passed"
    end
  end

  describe "reviews" do
    test "a build's changes can be rejected, then approved", %{project: project, user: user} do
      processed_build(project, %{git_branch: "main"}, [{"a.png", png(5)}])

      build =
        processed_build(project, %{git_branch: "feature", git_commit_sha: @b}, [{"a.png", png(50)}])

      {:ok, rejected} = Snapshots.reject_build(build, user.account)
      assert Snapshots.status(rejected, project) == "rejected"
      assert rejected.rejected_by_account_id == user.account.id
      assert {:ok, %{status: "rejected", rejected_by_account_id: account_id}} = Snapshots.get_commit(project, @b)
      assert account_id == user.account.id

      {:ok, approved} = Snapshots.approve_build(rejected, github_handle: "octocat")
      assert Snapshots.status(approved, project) == "approved"
      assert %Build{rejected_at: nil, rejected_by_account_id: nil, approved_by_github_handle: "octocat"} = approved
    end

    test "builds without changes can't be reviewed", %{project: project, user: user} do
      processed_build(project, %{git_branch: "main"}, [{"a.png", png(5)}])
      build = processed_build(project, %{git_branch: "feature"}, [{"a.png", png(5)}, {"new.png", png(9)}])

      assert {:error, :not_reviewable} = Snapshots.reject_build(build, user.account)
      assert {:error, :not_reviewable} = Snapshots.approve_build(build, user.account)
    end
  end

  describe "commits" do
    test "pools a commit's shards and sets, and a shard's missing images don't count as removed", %{project: project} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}, {"b.png", png(30)}])
      processed_build(project, %{set_name: "tablet", git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])

      pr = %{git_branch: "feature", git_commit_sha: @b, merge_base_sha: @a, pull_request_number: 7}
      # Each phone shard renders one image, so on its own it finds the other one removed.
      processed_build(project, pr, [{"a.png", png(50)}])
      processed_build(project, pr, [{"b.png", png(30)}])
      processed_build(project, Map.put(pr, :set_name, "tablet"), [{"a.png", png(5)}])

      assert {:ok, commit} = Snapshots.get_commit(project, @b)

      assert {commit.status, commit.changed_count, commit.unchanged_count, commit.removed_count, commit.runs_count} ==
               {"needs_review", 1, 2, 0, 3}

      assert commit.set_names == ["phone", "tablet"]
      assert {commit.baseline_commit_sha, commit.baseline_git_branch} == {@a, "main"}

      assert project |> Snapshots.commit_images(@b) |> Enum.map(&{&1.set_name, &1.name, &1.status}) == [
               {"phone", "a.png", "changed"},
               {"phone", "b.png", "unchanged"},
               {"tablet", "a.png", "unchanged"}
             ]
    end

    test "a rerun replaces the images it renders again", %{project: project} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      pr = %{git_branch: "feature", git_commit_sha: @b, merge_base_sha: @a}
      processed_build(project, pr, [{"a.png", png(50)}])
      assert {:ok, %{status: "needs_review"}} = Snapshots.get_commit(project, @b)

      processed_build(project, pr, [{"a.png", png(5)}])

      assert {:ok, %{status: "passed", changed_count: 0, unchanged_count: 1, runs_count: 2}} =
               Snapshots.get_commit(project, @b)
    end

    test "a commit takes its worst set's status and is approved as a whole", %{project: project, user: user} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      processed_build(project, %{set_name: "tablet", git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      pr = %{git_branch: "feature", git_commit_sha: @b, merge_base_sha: @a}
      phone = processed_build(project, pr, [{"a.png", png(50)}])
      processed_build(project, Map.put(pr, :set_name, "tablet"), [{"a.png", png(60)}])

      {:ok, _} = Snapshots.approve_build(phone, user.account)
      # One set approved, the other still waiting: the commit waits.
      assert {:ok, %{status: "needs_review"}} = Snapshots.get_commit(project, @b)

      assert {:ok, %{status: "approved", approved_by_account_id: account_id}} =
               Snapshots.approve_commit(project, @b, user.account)

      assert account_id == user.account.id

      assert {:ok, %{status: "rejected"}} = Snapshots.reject_commit(project, @b, user.account)
    end

    test "keeps the completion signal that arrives before the commit's first build", %{project: project} do
      Snapshots.signal_complete(project, @b)
      assert {:error, :not_found} = Snapshots.get_commit(project, @b)

      processed_build(project, %{git_branch: "feature", git_commit_sha: @b}, [{"a.png", png(5)}])

      assert {:ok, commit} = Snapshots.get_commit(project, @b)
      assert Snapshots.Commit.completeness(commit) == :complete
    end
  end

  describe "library" do
    test "holds each set's images at its latest default-branch commit, pooled over its shards", %{project: project} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [
        {"a.png", png(5)},
        {"b.png", png(30)},
        {"c.png", png(40)}
      ])

      processed_build(project, %{set_name: "tablet", git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      # Phone's next commit runs in two shards, each finding the other's image removed; c.png left the suite.
      processed_build(project, %{git_branch: "main", git_commit_sha: @b}, [{"a.png", png(50)}])
      processed_build(project, %{git_branch: "main", git_commit_sha: @b}, [{"b.png", png(30)}])
      # Pull requests never become the library.
      processed_build(project, %{git_branch: "feature", git_commit_sha: @c}, [{"z.png", png(60)}])

      assert project |> Snapshots.library_sources() |> Enum.map(&{&1.set_name, &1.git_commit_sha}) == [
               {"phone", @b},
               {"tablet", @a}
             ]

      library = Snapshots.list_library_images(project)

      assert library.total_count == 3

      assert Enum.map(library.images, &{&1.set_name, &1.name, &1.content_hash}) == [
               {"phone", "a.png", hash(png(50))},
               {"tablet", "a.png", hash(png(5))},
               {"phone", "b.png", hash(png(30))}
             ]
    end

    test "searches names, groups and tags literally, and pages by group and name", %{project: project} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [
        {"Home.png", png(5), %{group: "Screens", tags: %{"theme" => "dark"}}},
        {"Settings_100%.png", png(10)},
        {"button.png", png(20), %{display_name: "Primary button"}}
      ])

      names = fn opts -> project |> Snapshots.list_library_images(opts) |> Map.fetch!(:images) |> Enum.map(& &1.name) end

      assert names.([]) == ["button.png", "Settings_100%.png", "Home.png"]
      assert names.(page: 2, page_size: 2) == ["Home.png"]
      assert names.(search: "theme=DARK") == ["Home.png"]
      assert names.(search: "screens") == ["Home.png"]
      assert names.(search: "primary") == ["button.png"]
      # `%` and `_` match themselves, not any text.
      assert names.(search: "0%") == ["Settings_100%.png"]
      assert names.(search: "_") == ["Settings_100%.png"]
      assert Snapshots.count_library_images(project, search: "png") == 3
      # A group matches exactly, unlike a search.
      assert names.(group: "Screens") == ["Home.png"]
      assert names.(group: "screens") == []
      assert Snapshots.library_groups(project) == [%{group: "Screens", count: 1}]
    end

    test "default-branch builds store thumbnails, which pull request images fall back from", %{project: project} do
      main = processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5, 1200, 800)}])

      pr =
        processed_build(project, %{git_branch: "feature", git_commit_sha: @b, merge_base_sha: @a}, [
          {"a.png", png(50, 1200, 800)}
        ])

      [main_image] = Snapshots.list_images(main)
      [pr_image] = Snapshots.list_images(pr)

      # Scaled by 0.4 to fit 600×320.
      assert {:ok, thumbnail} = Snapshots.image_binary(project, main_image, :thumbnail)
      assert Diff.dimensions(thumbnail) == {:ok, {480, 320}}
      assert Snapshots.image_binary(project, pr_image, :thumbnail) == Snapshots.image_binary(project, pr_image, :head)
    end

    test "an image's history keeps the default branch's versions that looked different, removal included",
         %{project: project} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      # A pull request's change hasn't landed, so it isn't history.
      processed_build(project, %{git_branch: "feature", git_commit_sha: @c, merge_base_sha: @a}, [{"a.png", png(50)}])
      processed_build(project, %{git_branch: "main", git_commit_sha: @b}, [{"a.png", png(50)}])
      # Rendered again identically: not a new version.
      processed_build(project, %{git_branch: "main", git_commit_sha: @d}, [{"a.png", png(50)}])
      removed = String.duplicate("e", 40)
      processed_build(project, %{git_branch: "main", git_commit_sha: removed}, [{"b.png", png(30)}])

      versions = fn opts ->
        history = Snapshots.image_history(project, "phone", "a.png", opts)
        {Enum.map(history.versions, &{&1.build.git_commit_sha, &1.image.status}), history.more?}
      end

      assert versions.([]) == {[{removed, "removed"}, {@b, "changed"}, {@a, "added"}], false}

      # Paged newest first, each page after the previous page's last build.
      assert versions.(limit: 2) == {[{removed, "removed"}, {@b, "changed"}], true}
      [_, %{build: second}] = Snapshots.image_history(project, "phone", "a.png", limit: 2).versions
      assert versions.(limit: 2, before: second) == {[{@a, "added"}], false}

      assert Enum.map(Snapshots.image_history(project, "phone", "b.png").versions, & &1.image.status) == ["added"]
    end
  end

  describe "analytics/2" do
    test "counts snapshot runs, commits with visual changes and the default branch's snapshots", %{project: project} do
      processed_build(project, %{git_branch: "main", git_commit_sha: @a}, [{"a.png", png(5)}])
      # Two sets of one commit are two runs.
      processed_build(project, %{git_branch: "main", git_commit_sha: @b}, [{"a.png", png(5)}, {"b.png", png(30)}])
      processed_build(project, %{set_name: "tablet", git_branch: "main", git_commit_sha: @b}, [{"a.png", png(5)}])
      # Changed against main's newest build: a visual change, in two shards that make one commit.
      feature = %{git_branch: "feature", git_commit_sha: @c}
      processed_build(project, feature, [{"a.png", png(50)}])
      processed_build(project, feature, [{"b.png", png(30)}])
      # Only adds a snapshot: nothing to review.
      processed_build(project, %{git_branch: "other", git_commit_sha: @d}, [
        {"a.png", png(5)},
        {"b.png", png(30)},
        {"c.png", png(60)}
      ])

      # An upload that never finished isn't a run.
      {:ok, _abandoned, _} =
        Snapshots.create_build(project, %{set_name: "phone", git_commit_sha: @d}, [
          %{name: "a.png", content_hash: hash(png(70))}
        ])

      now = DateTime.utc_now()
      analytics = Snapshots.analytics(project, start_datetime: DateTime.add(now, -7, :day), end_datetime: now)

      assert analytics.snapshot_runs.count == 6
      assert analytics.visual_changes.count == 1
      # The latest main build of each set: 2 phone snapshots and 1 tablet snapshot.
      assert analytics.snapshots.count == 3
      assert List.last(analytics.snapshot_runs.values) == 6
      assert length(analytics.snapshot_runs.dates) == 8
      # Days before main's first upload have no snapshot count, rather than zero.
      assert analytics.snapshots.values == List.duplicate(nil, 7) ++ [3]
    end
  end

  describe "Diff.compare/2" do
    test "counts differing pixels exactly" do
      assert {:ok, %{ratio: ratio, diff_png: diff}} = Diff.compare(png(50), png(5))
      assert_in_delta ratio, 200 / 8000, 1.0e-9
      assert {:ok, {100, 80}} = Diff.dimensions(diff)

      assert {:ok, %{ratio: +0.0, diff_png: nil}} = Diff.compare(png(5), png(5))
    end
  end
end
