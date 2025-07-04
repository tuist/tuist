defmodule Tuist.BundlesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Bundles
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(DateTime, :utc_now, fn -> ~U[2024-08-10 02:00:00Z] end)
    :ok
  end

  describe "create_bundle/1" do
    test "creates a bundle" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      id = UUIDv7.generate()

      # When
      {:ok, bundle} =
        Bundles.create_bundle(%{
          id: id,
          name: "App",
          app_bundle_id: "dev.tuist.app",
          install_size: 1024,
          download_size: 1024,
          supported_platforms: [
            :ios,
            :ios_simulator
          ],
          version: "1.0.0",
          git_branch: "main",
          project_id: project_id
        })

      # Then
      assert bundle.id == id
    end

    test "raises if an artifact type is invalid" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      id = UUIDv7.generate()

      # When
      assert_raise RuntimeError, fn ->
        Bundles.create_bundle(%{
          id: id,
          name: "App",
          app_bundle_id: "dev.tuist.app",
          install_size: 1024,
          download_size: 1024,
          supported_platforms: [
            :ios,
            :ios_simulator
          ],
          version: "1.0.0",
          git_branch: "main",
          project_id: project_id,
          artifacts: [
            %{
              "artifact_type" => "invalid",
              "path" => "Tuist.app/Tuist.bundle",
              "shasum" => "092378b10a45c64bbf5cb8846dd13ff03e728f7925994b812c40b8922644d325",
              "size" => 1183
            }
          ]
        })
      end
    end
  end

  describe "get_bundle/1" do
    test "returns bundle by ID" do
      # Given
      bundle = BundlesFixtures.bundle_fixture()

      # When
      {:ok, got} = Bundles.get_bundle(bundle.id)

      # Then
      assert got.id == bundle.id
    end

    test "when no bundle with the given ID exists" do
      # When
      got = Bundles.get_bundle(UUIDv7.generate())

      # Then
      assert {:error, :not_found} == got
    end
  end

  describe "install_size_deviation/1" do
    test "when bundle is not from the main branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 2048,
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "feat/new-feature",
        install_size: 1500,
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_branch: "feat/new-feature",
          install_size: 1024,
          inserted_at: ~U[2024-01-01 04:00:00Z]
        )

      # When
      got = Bundles.install_size_deviation(bundle)

      # Then
      assert got == -0.5
    end

    test "when bundle is from the main branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 1024,
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_branch: "main",
          install_size: 2048,
          inserted_at: ~U[2024-01-01 02:00:00Z]
        )

      # When
      got = Bundles.install_size_deviation(bundle)

      # Then
      assert got == 1.0
    end

    test "when there is no other bundle" do
      # Given
      project = ProjectsFixtures.project_fixture()

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_branch: "main",
          install_size: 2048
        )

      # When
      got = Bundles.install_size_deviation(bundle)

      # Then
      assert got == 0.0
    end

    test "when there is only bundle from a non-main branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        install_size: 1024,
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_branch: "main",
          install_size: 2048,
          inserted_at: ~U[2024-01-01 02:00:00Z]
        )

      # When
      got = Bundles.install_size_deviation(bundle)

      # Then
      assert got == 1.0
    end
  end

  describe "last_bundle/1" do
    test "when there is last bundle" do
      # Given
      project = ProjectsFixtures.project_fixture()

      last_bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1024,
          inserted_at: ~U[2024-01-01 02:00:00Z]
        )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_branch: "main",
          install_size: 2048,
          inserted_at: ~U[2024-01-01 03:00:00Z]
        )

      # When
      got = Bundles.last_project_bundle(project, bundle: bundle)

      # Then
      assert got == last_bundle
    end

    test "when there is no last bundle" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        install_size: 1024,
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_branch: "main",
          install_size: 2048,
          inserted_at: ~U[2024-01-01 01:00:00Z]
        )

      # When
      got = Bundles.last_project_bundle(project, bundle: bundle)

      # Then
      assert got == nil
    end
  end

  describe "project_bundle_install_size_analytics/2" do
    test "returns bundle install size analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 4000,
        inserted_at: ~U[2024-04-30 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 3000,
        inserted_at: ~U[2024-04-29 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "feat/my-feature",
        install_size: 3000,
        inserted_at: ~U[2024-04-28 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 1500,
        inserted_at: ~U[2024-04-27 04:00:00Z]
      )

      # When
      got =
        Bundles.project_bundle_install_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -2),
          git_branch: "main"
        )

      assert got == [
               %{date: ~D[2024-04-28], bundle_install_size: 1500},
               %{date: ~D[2024-04-29], bundle_install_size: 3000},
               %{date: ~D[2024-04-30], bundle_install_size: 4000}
             ]
    end

    test "returns bundle install size analytics for the last 90 days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 4000,
        inserted_at: ~U[2024-04-30 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 3000,
        inserted_at: ~U[2024-03-29 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "feat/my-feature",
        install_size: 3000,
        inserted_at: ~U[2024-02-28 04:00:00Z]
      )

      # When
      got =
        Bundles.project_bundle_install_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -90),
          git_branch: "main"
        )

      assert got == [
               %{bundle_install_size: 0, date: ~D[2024-02-01]},
               %{bundle_install_size: 3000, date: ~D[2024-03-01]},
               %{bundle_install_size: 4000, date: ~D[2024-04-01]}
             ]
    end

    test "fills gaps with previous 7 days data and updates when new data arrives" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-05-10 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Create bundles with gaps to test fallback behavior
      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 1000,
        # Friday
        inserted_at: ~U[2024-05-03 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 2000,
        inserted_at: ~U[2024-05-02 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 3500,
        # Monday - new data
        inserted_at: ~U[2024-05-06 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 4200,
        inserted_at: ~U[2024-05-09 04:00:00Z]
      )

      # When
      got =
        Bundles.project_bundle_install_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -9),
          git_branch: "main"
        )

      # Then
      assert got == [
               %{date: ~D[2024-05-01], bundle_install_size: 0},
               %{date: ~D[2024-05-02], bundle_install_size: 2000},
               %{date: ~D[2024-05-03], bundle_install_size: 1000},
               %{date: ~D[2024-05-04], bundle_install_size: 1000},
               %{date: ~D[2024-05-05], bundle_install_size: 1000},
               %{date: ~D[2024-05-06], bundle_install_size: 3500},
               %{date: ~D[2024-05-07], bundle_install_size: 3500},
               %{date: ~D[2024-05-08], bundle_install_size: 3500},
               %{date: ~D[2024-05-09], bundle_install_size: 4200},
               %{date: ~D[2024-05-10], bundle_install_size: 4200}
             ]
    end
  end

  describe "bundle_download_size_analytics/2" do
    test "returns bundle download size analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 4000,
        inserted_at: ~U[2024-04-30 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 3000,
        inserted_at: ~U[2024-04-29 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "feat/my-feature",
        install_size: 3000,
        inserted_at: ~U[2024-04-28 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        install_size: 1500,
        inserted_at: ~U[2024-04-27 04:00:00Z]
      )

      # When
      got =
        Bundles.bundle_download_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -2),
          git_branch: "main"
        )

      assert got == [
               %{date: ~D[2024-04-28], bundle_download_size: 1024},
               %{date: ~D[2024-04-29], bundle_download_size: 3000},
               %{date: ~D[2024-04-30], bundle_download_size: 4000}
             ]
    end

    test "returns bundle download size analytics for the last 90 days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 4000,
        inserted_at: ~U[2024-04-30 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 3000,
        inserted_at: ~U[2024-03-29 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "feat/my-feature",
        install_size: 3000,
        inserted_at: ~U[2024-02-28 04:00:00Z]
      )

      # When
      got =
        Bundles.bundle_download_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -90),
          git_branch: "main"
        )

      assert got == [
               %{bundle_download_size: 0, date: ~D[2024-02-01]},
               %{bundle_download_size: 3000, date: ~D[2024-03-01]},
               %{bundle_download_size: 4000, date: ~D[2024-04-01]}
             ]
    end

    test "fills gaps with previous 7 days data and updates when new data arrives for download size" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-05-10 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 1000,
        # Friday
        inserted_at: ~U[2024-05-03 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 2000,
        inserted_at: ~U[2024-05-02 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 3500,
        inserted_at: ~U[2024-05-06 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        download_size: 4200,
        inserted_at: ~U[2024-05-09 04:00:00Z]
      )

      # When - get analytics for the period
      got =
        Bundles.bundle_download_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -9),
          git_branch: "main"
        )

      # Then
      assert got == [
               %{date: ~D[2024-05-01], bundle_download_size: 0},
               %{date: ~D[2024-05-02], bundle_download_size: 2000},
               %{date: ~D[2024-05-03], bundle_download_size: 1000},
               %{date: ~D[2024-05-04], bundle_download_size: 1000},
               %{date: ~D[2024-05-05], bundle_download_size: 1000},
               %{date: ~D[2024-05-06], bundle_download_size: 3500},
               %{date: ~D[2024-05-07], bundle_download_size: 3500},
               %{date: ~D[2024-05-08], bundle_download_size: 3500},
               %{date: ~D[2024-05-09], bundle_download_size: 4200},
               %{date: ~D[2024-05-10], bundle_download_size: 4200}
             ]
    end
  end

  describe "format_bytes/1" do
    test "formats bytes when 2 bytes" do
      assert "2 B" == Bundles.format_bytes(2)
    end

    test "formats bytes when 1024 bytes" do
      assert "1.0 KB" == Bundles.format_bytes(1024)
    end

    test "formats bytes when 1_000_000 bytes" do
      assert "1.0 MB" == Bundles.format_bytes(1_000_000)
    end

    test "formats bytes when 1_000_000_000 bytes" do
      assert "1.0 GB" == Bundles.format_bytes(1_000_000_000)
    end
  end

  describe "default_app/1" do
    test "returns nil when there are no app bundles" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Bundles.default_app(project)

      # Then
      assert result == nil
    end

    test "returns the iOS app name when available" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        name: "MacApp",
        supported_platforms: [:macos],
        git_branch: "main",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        name: "iOSApp",
        supported_platforms: [:ios],
        git_branch: "main",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      # When
      result = Bundles.default_app(project)

      # Then
      assert result == "iOSApp"
    end

    test "returns the iOS app with the latest bundle when available" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        name: "AppOne",
        supported_platforms: [:macos],
        git_branch: "main",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        name: "AppTwo",
        supported_platforms: [:ios],
        git_branch: "main",
        inserted_at: ~U[2024-02-01 02:00:00Z]
      )

      # When
      result = Bundles.default_app(project)

      # Then
      assert result == "AppTwo"
    end

    test "returns the first app name when no iOS app is available" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        name: "TvApp",
        supported_platforms: [:tvos],
        git_branch: "main",
        inserted_at: ~U[2024-02-01 02:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        name: "MacApp",
        supported_platforms: [:macos],
        git_branch: "main",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      # When
      result = Bundles.default_app(project)

      # Then
      assert result == "TvApp"
    end
  end

  describe "has_bundles_in_project_default_branch?/1" do
    test "returns true when there are bundles in the project's default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main"
      )

      # When
      result = Bundles.has_bundles_in_project_default_branch?(project)

      # Then
      assert result == true
    end

    test "returns false when there are no bundles in the project's default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "feature/test"
      )

      # When
      result = Bundles.has_bundles_in_project_default_branch?(project)

      # Then
      assert result == false
    end

    test "returns false when there are no bundles at all in the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Bundles.has_bundles_in_project_default_branch?(project)

      # Then
      assert result == false
    end
  end

  describe "delete_bundle!/1" do
    test "deletes a bundle successfully" do
      # Given
      bundle = BundlesFixtures.bundle_fixture()

      # When
      Bundles.delete_bundle!(bundle)

      # Then
      assert Bundles.get_bundle(bundle.id) == {:error, :not_found}
    end
  end
end
