defmodule Tuist.Bundles.ArtifactBackfillTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Bundles.Artifact
  alias Tuist.Bundles.ArtifactBackfill
  alias Tuist.Bundles.ArtifactIngest
  alias Tuist.Bundles.Bundle
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "run/0" do
    test "replicates artifacts of unreplicated bundles to ClickHouse and flips the flag" do
      # Given — two bundles whose dual-write never landed in CH (e.g. CH
      # was unavailable at create-time, or this is pre-dual-write history).
      project = ProjectsFixtures.project_fixture()
      [bundle_1, bundle_2] = create_unreplicated_bundles(project, 2)

      [a1] = insert_pg_artifacts(bundle_1, [{"App.app", "aaa", 4_000_000_000}])

      [a2_parent, a2_child] =
        insert_pg_artifacts(bundle_2, [
          {"App.app", "bbb", 1024},
          {"App.app/Info.plist", "ccc", 512}
        ])

      # When
      assert {2, 3} = ArtifactBackfill.run()

      # Then — both bundles' artifacts now exist in CH, the larger one
      # round-trips through `Int64` (the original motivation for this
      # whole migration), and both bundles are marked replicated so the
      # backfill won't pick them up again.
      ch_artifacts =
        ClickHouseRepo.all(from(a in ArtifactIngest, order_by: [asc: a.bundle_id, asc: a.path]))

      assert length(ch_artifacts) == 3

      assert Enum.find(ch_artifacts, &(&1.id == a1.id)).size == 4_000_000_000
      assert Enum.find(ch_artifacts, &(&1.id == a2_parent.id)).size == 1024
      assert Enum.find(ch_artifacts, &(&1.id == a2_child.id)).size == 512

      assert Repo.get!(Bundle, bundle_1.id).artifacts_replicated_to_ch == true
      assert Repo.get!(Bundle, bundle_2.id).artifacts_replicated_to_ch == true
    end

    test "skips bundles that are already replicated" do
      # Given — one replicated, one not.
      project = ProjectsFixtures.project_fixture()
      already_replicated = BundlesFixtures.bundle_fixture(project: project)
      [unreplicated] = create_unreplicated_bundles(project, 1)

      insert_pg_artifacts(already_replicated, [{"Already.app", "old", 1}])
      [pending_artifact] = insert_pg_artifacts(unreplicated, [{"Pending.app", "new", 2}])

      # When
      assert {1, 1} = ArtifactBackfill.run()

      # Then — only the unreplicated bundle's artifact landed in CH.
      ch_artifacts = ClickHouseRepo.all(from(a in ArtifactIngest))
      assert Enum.map(ch_artifacts, & &1.id) == [pending_artifact.id]
    end

    test "marks empty bundles replicated without writing to CH" do
      # Given — a bundle that pre-dates dual-write but happens to have
      # zero artifacts (a degenerate case the backfill should still
      # converge through).
      project = ProjectsFixtures.project_fixture()
      [empty_bundle] = create_unreplicated_bundles(project, 1)

      # When
      assert {1, 0} = ArtifactBackfill.run()

      # Then — flag flipped, CH untouched for this bundle.
      assert Repo.get!(Bundle, empty_bundle.id).artifacts_replicated_to_ch == true
      assert ClickHouseRepo.all(from(a in ArtifactIngest)) == []
    end

    test "is a no-op when every bundle is already replicated" do
      project = ProjectsFixtures.project_fixture()
      BundlesFixtures.bundle_fixture(project: project)

      assert {0, 0} = ArtifactBackfill.run()
      assert ClickHouseRepo.all(from(a in ArtifactIngest)) == []
    end
  end

  defp create_unreplicated_bundles(project, count) do
    # Use the fixture (which goes through `Bundles.create_bundle/2`) so
    # the bundle has every required column set, then flip the flag back
    # to mimic a bundle whose dual-write never landed.
    bundles = for _ <- 1..count, do: BundlesFixtures.bundle_fixture(project: project)
    bundle_ids = Enum.map(bundles, & &1.id)

    Repo.update_all(
      from(b in Bundle, where: b.id in ^bundle_ids),
      set: [artifacts_replicated_to_ch: false]
    )

    bundles
  end

  defp insert_pg_artifacts(bundle, specs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(specs, fn {path, shasum, size} ->
        %{
          id: UUIDv7.generate(),
          bundle_id: bundle.id,
          artifact_type: :file,
          path: path,
          size: size,
          shasum: shasum,
          artifact_id: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Artifact, rows)
    rows
  end
end
