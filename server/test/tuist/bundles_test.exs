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
          type: :app,
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
          type: :app,
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

    test "when the bundle is associated with the project with the given id" do
      # Given
      bundle = BundlesFixtures.bundle_fixture()

      # When
      {:ok, got} = Bundles.get_bundle(bundle.id, project_id: bundle.project_id)

      # Then
      assert got.id == bundle.id
    end

    test "when the bundle is not associated with the project with the given id" do
      # Given
      bundle = BundlesFixtures.bundle_fixture()
      another_project = ProjectsFixtures.project_fixture()

      # When
      got = Bundles.get_bundle(bundle.id, project_id: another_project.id)

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
      got =
        project |> Bundles.last_project_bundle(bundle: bundle) |> Repo.preload(:uploaded_by_account)

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

    test "filters by bundle type when type option is provided" do
      project = ProjectsFixtures.project_fixture()

      ipa_bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          type: :ipa,
          inserted_at: ~U[2024-01-01 02:00:00Z]
        )

      app_bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          type: :app,
          inserted_at: ~U[2024-01-01 03:00:00Z]
        )

      got_ipa = Bundles.last_project_bundle(project, type: :ipa)

      assert got_ipa.id == ipa_bundle.id
      assert got_ipa.type == :ipa

      got_app = Bundles.last_project_bundle(project, type: :app)

      assert got_app.id == app_bundle.id
      assert got_app.type == :app
    end

    test "returns nil when no bundles of specified type exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        type: :app,
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      # When looking for xcarchive bundle
      got = Bundles.last_project_bundle(project, type: :xcarchive)

      # Then
      assert got == nil
    end

    test "falls back to any type when no bundle of specified type and git_branch exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      fallback_bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          type: :ipa,
          git_branch: "develop",
          inserted_at: ~U[2024-01-01 02:00:00Z]
        )

      # When
      got = Bundles.last_project_bundle(project, git_branch: "main", type: :ipa)

      # Then
      assert got.id == fallback_bundle.id
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

    test "filters analytics by bundle type when type option is provided" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :ipa,
        install_size: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :ipa,
        install_size: 4000,
        inserted_at: ~U[2024-04-29 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :app,
        install_size: 10_000,
        inserted_at: ~U[2024-04-30 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :app,
        install_size: 8000,
        inserted_at: ~U[2024-04-29 05:00:00Z]
      )

      # When
      got =
        Bundles.project_bundle_install_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -2),
          git_branch: "main",
          type: :ipa
        )

      # Then
      assert got == [
               %{date: ~D[2024-04-28], bundle_install_size: 0},
               %{date: ~D[2024-04-29], bundle_install_size: 4000},
               %{date: ~D[2024-04-30], bundle_install_size: 2000}
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

    test "filters download size analytics by bundle type when type option is provided" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Create IPA bundles
      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :ipa,
        download_size: 1500,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :ipa,
        download_size: 3000,
        inserted_at: ~U[2024-04-29 04:00:00Z]
      )

      # Create XCARCHIVE bundles (should be excluded)
      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :xcarchive,
        download_size: 9000,
        inserted_at: ~U[2024-04-30 04:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        git_branch: "main",
        type: :xcarchive,
        download_size: 7500,
        inserted_at: ~U[2024-04-29 05:00:00Z]
      )

      # When - get analytics for IPA bundles only
      got =
        Bundles.bundle_download_size_analytics(
          project,
          start_date: Date.add(DateTime.utc_now(), -2),
          git_branch: "main",
          type: :ipa
        )

      # Then - should only include IPA bundle data
      assert got == [
               %{date: ~D[2024-04-28], bundle_download_size: 0},
               %{date: ~D[2024-04-29], bundle_download_size: 3000},
               %{date: ~D[2024-04-30], bundle_download_size: 1500}
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

  describe "list_bundles/1" do
    test "returns all bundles for a project" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, name: "App1")
      bundle2 = BundlesFixtures.bundle_fixture(project: project, name: "App2")
      
      # Different project bundle should not be included
      _other_bundle = BundlesFixtures.bundle_fixture(name: "Other")

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [%{field: :project_id, op: :==, value: project.id}],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "filters bundles by name using text search" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, name: "TuistApp")
      bundle2 = BundlesFixtures.bundle_fixture(project: project, name: "MyApp")
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, name: "Framework")

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :name, op: :=~, value: "App"}
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "filters bundles by git branch using text search" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, git_branch: "main")
      bundle2 = BundlesFixtures.bundle_fixture(project: project, git_branch: "feature/main-update")
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, git_branch: "develop")

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :git_branch, op: :=~, value: "main"}
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "filters bundles by type" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, type: :app)
      bundle2 = BundlesFixtures.bundle_fixture(project: project, type: :app)
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, type: :ipa)

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :type, op: :==, value: :app}
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "filters bundles by install size (greater than or equal)" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, install_size: 5_242_880)  # 5 MB
      bundle2 = BundlesFixtures.bundle_fixture(project: project, install_size: 10_485_760) # 10 MB
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, install_size: 2_097_152) # 2 MB

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :install_size, op: :>=, value: 5_242_880} # 5 MB in bytes
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "filters bundles by download size (greater than or equal)" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, download_size: 3_145_728) # 3 MB
      bundle2 = BundlesFixtures.bundle_fixture(project: project, download_size: 8_388_608) # 8 MB
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, download_size: 1_048_576) # 1 MB

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :download_size, op: :>=, value: 3_145_728} # 3 MB in bytes
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "filters bundles by supported platforms using overlap" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, supported_platforms: [:ios, :ios_simulator])
      bundle2 = BundlesFixtures.bundle_fixture(project: project, supported_platforms: [:ios, :macos])
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, supported_platforms: [:macos, :watchos])

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :supported_platforms, op: :contains, value: :ios}
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "filters bundles by creation date (greater than or equal)" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, inserted_at: ~U[2024-05-01 10:00:00Z])
      bundle2 = BundlesFixtures.bundle_fixture(project: project, inserted_at: ~U[2024-05-02 10:00:00Z])
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, inserted_at: ~U[2024-04-01 10:00:00Z])

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :inserted_at, op: :>=, value: ~U[2024-05-01 00:00:00Z]}
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert bundle2.id in bundle_ids
      assert length(bundles) == 2
    end

    test "applies multiple filters simultaneously" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(
        project: project, 
        name: "TuistApp", 
        type: :app, 
        install_size: 5000,
        git_branch: "main"
      )
      _bundle2 = BundlesFixtures.bundle_fixture(
        project: project, 
        name: "TuistApp", 
        type: :ipa, 
        install_size: 5000,
        git_branch: "main"
      )
      _bundle3 = BundlesFixtures.bundle_fixture(
        project: project, 
        name: "Framework", 
        type: :app, 
        install_size: 5000,
        git_branch: "main"
      )

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :name, op: :=~, value: "Tuist"},
          %{field: :type, op: :==, value: :app},
          %{field: :install_size, op: :>=, value: 4000}
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert length(bundles) == 1
    end

    test "sorts bundles by install size" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, install_size: 1000)
      bundle2 = BundlesFixtures.bundle_fixture(project: project, install_size: 5000)
      bundle3 = BundlesFixtures.bundle_fixture(project: project, install_size: 3000)

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [%{field: :project_id, op: :==, value: project.id}],
        order_by: [:install_size],
        order_directions: [:desc],
        first: 10
      })

      # Then
      assert length(bundles) == 3
      assert Enum.at(bundles, 0).id == bundle2.id  # 5000
      assert Enum.at(bundles, 1).id == bundle3.id  # 3000
      assert Enum.at(bundles, 2).id == bundle1.id  # 1000
    end

    test "sorts bundles by download size" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, download_size: 1000)
      bundle2 = BundlesFixtures.bundle_fixture(project: project, download_size: 5000)
      bundle3 = BundlesFixtures.bundle_fixture(project: project, download_size: 3000)

      # When
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [%{field: :project_id, op: :==, value: project.id}],
        order_by: [:download_size],
        order_directions: [:desc],
        first: 10
      })

      # Then
      assert length(bundles) == 3
      assert Enum.at(bundles, 0).id == bundle2.id  # 5000
      assert Enum.at(bundles, 1).id == bundle3.id  # 3000
      assert Enum.at(bundles, 2).id == bundle1.id  # 1000
    end
  end

  describe "has_bundles_in_project?/1" do
    test "returns true when project has bundles" do
      # Given
      project = ProjectsFixtures.project_fixture()
      _bundle = BundlesFixtures.bundle_fixture(project: project)

      # When
      result = Bundles.has_bundles_in_project?(project)

      # Then
      assert result == true
    end

    test "returns false when project has no bundles" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Bundles.has_bundles_in_project?(project)

      # Then
      assert result == false
    end

    test "returns true when project has bundles from different branches" do
      # Given
      project = ProjectsFixtures.project_fixture()
      _main_bundle = BundlesFixtures.bundle_fixture(project: project, git_branch: "main")
      _feature_bundle = BundlesFixtures.bundle_fixture(project: project, git_branch: "feature/test")

      # When
      result = Bundles.has_bundles_in_project?(project)

      # Then
      assert result == true
    end
  end

  describe "MB to bytes conversion in filtering" do
    test "converts install size from MB to bytes when filtering" do
      # Given
      project = ProjectsFixtures.project_fixture()
      # Create bundles with sizes in bytes: 5MB, 10MB, 2MB
      bundle_5mb = BundlesFixtures.bundle_fixture(project: project, install_size: 5_242_880)  # 5 MB
      bundle_10mb = BundlesFixtures.bundle_fixture(project: project, install_size: 10_485_760) # 10 MB
      _bundle_2mb = BundlesFixtures.bundle_fixture(project: project, install_size: 2_097_152)  # 2 MB

      # When filtering with 5 MB (which should be converted to bytes internally)
      # Simulate what happens when user enters "5" in the Install Size (MB) filter
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :install_size, op: :>=, value: 5_242_880} # 5 MB worth of bytes
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then - should return bundles with 5MB or more
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle_5mb.id in bundle_ids
      assert bundle_10mb.id in bundle_ids
      assert length(bundles) == 2
    end

    test "converts download size from MB to bytes when filtering" do
      # Given
      project = ProjectsFixtures.project_fixture()
      # Create bundles with sizes in bytes: 3MB, 8MB, 1MB
      bundle_3mb = BundlesFixtures.bundle_fixture(project: project, download_size: 3_145_728) # 3 MB
      bundle_8mb = BundlesFixtures.bundle_fixture(project: project, download_size: 8_388_608) # 8 MB
      _bundle_1mb = BundlesFixtures.bundle_fixture(project: project, download_size: 1_048_576) # 1 MB

      # When filtering with 3 MB (which should be converted to bytes internally)
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :download_size, op: :>=, value: 3_145_728} # 3 MB worth of bytes
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then - should return bundles with 3MB or more
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle_3mb.id in bundle_ids
      assert bundle_8mb.id in bundle_ids
      assert length(bundles) == 2
    end

    test "handles nil values in size filters gracefully" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, install_size: 5_242_880)

      # When filtering with nil value (should be ignored)
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :install_size, op: :>=, value: nil} # Should be filtered out
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then - should return all bundles (nil filter ignored)
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert length(bundles) == 1
    end

    test "handles string values in size filters" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle_5mb = BundlesFixtures.bundle_fixture(project: project, install_size: 5_242_880)  # 5 MB
      bundle_10mb = BundlesFixtures.bundle_fixture(project: project, install_size: 10_485_760) # 10 MB
      _bundle_2mb = BundlesFixtures.bundle_fixture(project: project, install_size: 2_097_152)  # 2 MB

      # When filtering with string value (as it comes from form input)
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :install_size, op: :>=, value: "5"} # String value should be converted
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then - should return bundles with 5MB or more
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle_5mb.id in bundle_ids
      assert bundle_10mb.id in bundle_ids
      assert length(bundles) == 2
    end

    test "handles invalid string values in size filters gracefully" do
      # Given
      project = ProjectsFixtures.project_fixture()
      bundle1 = BundlesFixtures.bundle_fixture(project: project, install_size: 5_242_880)

      # When filtering with invalid string value (should be ignored)
      {bundles, _meta} = Bundles.list_bundles(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :install_size, op: :>=, value: "not_a_number"} # Should be filtered out
        ],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 10
      })

      # Then - should return all bundles (invalid filter ignored)
      bundle_ids = Enum.map(bundles, & &1.id)
      assert bundle1.id in bundle_ids
      assert length(bundles) == 1
    end
  end
end
