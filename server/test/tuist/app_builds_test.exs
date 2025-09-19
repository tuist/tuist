defmodule Tuist.AppBuildsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_preview/1" do
    test "creates a bundle preview" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          type: :app_bundle,
          display_name: "App",
          version: nil,
          bundle_identifier: nil
        )

      # Then
      assert Repo.all(Preview) == [preview]
    end

    test "creates an archive preview" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "dev.tuist.app"
        )

      # Then
      assert Repo.all(Preview) == [preview]
    end
  end

  describe "find_or_create_preview/1" do
    test "creates a new preview when none exists" do
      # Given
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        project_id: project.id,
        bundle_identifier: "com.example.app",
        version: "1.0.0",
        git_commit_sha: "abc123",
        created_by_account_id: project.account.id,
        display_name: "Test App",
        git_branch: "main",
        git_ref: "refs/heads/main",
        visibility: :private,
        supported_platforms: [:ios]
      }

      # When
      {:ok, preview} = AppBuilds.find_or_create_preview(attrs)

      # Then
      assert preview.project_id == project.id
      assert preview.bundle_identifier == "com.example.app"
      assert preview.version == "1.0.0"
      assert preview.git_commit_sha == "abc123"
      assert preview.created_by_account_id == project.account.id
      assert preview.display_name == "Test App"
      assert preview.git_branch == "main"
      assert preview.git_ref == "refs/heads/main"
      assert preview.visibility == :private
      assert preview.supported_platforms == [:ios]
    end

    test "returns existing preview when one matches all criteria" do
      # Given
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        project_id: project.id,
        bundle_identifier: "com.example.app",
        version: "1.0.0",
        git_commit_sha: "abc123",
        created_by_account_id: project.account.id,
        display_name: "Test App"
      }

      {:ok, existing_preview} = AppBuilds.create_preview(attrs)

      # When
      {:ok, found_preview} = AppBuilds.find_or_create_preview(attrs)

      # Then
      assert found_preview.id == existing_preview.id
      # Ensure only one preview exists
      assert length(Repo.all(Preview)) == 1
    end

    test "returns a preview when multiple matche all criteria" do
      # Given
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        project_id: project.id,
        bundle_identifier: "com.example.app",
        version: "1.0.0",
        git_commit_sha: "abc123",
        created_by_account_id: project.account.id,
        display_name: "Test App"
      }

      AppBuilds.create_preview(attrs)
      AppBuilds.create_preview(attrs)

      # When
      {:ok, found_preview} = AppBuilds.find_or_create_preview(attrs)

      # Then
      assert found_preview.bundle_identifier == attrs.bundle_identifier
    end

    test "creates new preview when project_id differs" do
      # Given
      project1 = ProjectsFixtures.project_fixture()
      project2 = ProjectsFixtures.project_fixture()

      attrs1 = %{
        project_id: project1.id,
        bundle_identifier: "com.example.app",
        version: "1.0.0",
        git_commit_sha: "abc123",
        created_by_account_id: project1.account.id,
        display_name: "Test App"
      }

      attrs2 = %{attrs1 | project_id: project2.id, created_by_account_id: project2.account.id}

      {:ok, _existing_preview} = AppBuilds.create_preview(attrs1)

      # When
      {:ok, new_preview} = AppBuilds.find_or_create_preview(attrs2)

      # Then
      assert new_preview.project_id == project2.id
      # Ensure two previews exist
      assert length(Repo.all(Preview)) == 2
    end

    test "creates new preview when bundle_identifier differs" do
      # Given
      project = ProjectsFixtures.project_fixture()

      attrs1 = %{
        project_id: project.id,
        bundle_identifier: "com.example.app1",
        version: "1.0.0",
        git_commit_sha: "abc123",
        created_by_account_id: project.account.id,
        display_name: "Test App"
      }

      attrs2 = %{attrs1 | bundle_identifier: "com.example.app2"}

      {:ok, _existing_preview} = AppBuilds.create_preview(attrs1)

      # When
      {:ok, new_preview} = AppBuilds.find_or_create_preview(attrs2)

      # Then
      assert new_preview.bundle_identifier == "com.example.app2"
      # Ensure two previews exist
      assert length(Repo.all(Preview)) == 2
    end

    test "finds existing preview with nil values" do
      # Given
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        project_id: project.id,
        bundle_identifier: nil,
        version: nil,
        git_commit_sha: nil,
        created_by_account_id: project.account.id,
        display_name: nil
      }

      {:ok, existing_preview} = AppBuilds.create_preview(attrs)

      # When
      {:ok, found_preview} = AppBuilds.find_or_create_preview(attrs)

      # Then
      assert found_preview.id == existing_preview.id
      # Ensure only one preview exists
      assert length(Repo.all(Preview)) == 1
    end
  end

  describe "preview_by_id/1" do
    test "returns a preview by id" do
      # Given
      preview =
        AppBuildsFixtures.preview_fixture(
          project: ProjectsFixtures.project_fixture(),
          type: :app_bundle,
          display_name: "App",
          version: nil,
          bundle_identifier: nil
        )

      # When
      {:ok, result} = AppBuilds.preview_by_id(preview.id)

      # Then
      assert result == preview
    end

    test "returns a preview by id with preloaded preview bundles" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      # When
      {:ok, result} = AppBuilds.preview_by_id(preview.id, preload: [:app_builds])

      # Then
      assert result.id == preview.id
      assert result.app_builds == []
    end

    test "returns an error when the id is invalid" do
      # Given
      invalid_id = "invalid-id"

      # When
      {:error, result} = AppBuilds.preview_by_id(invalid_id)

      # Then
      assert result ==
               "The provided preview ID invalid-id doesn't have a valid format."
    end

    test "returns not_found error when the preview is not found" do
      # Given
      preview_id = UUIDv7.generate()

      # When
      result = AppBuilds.preview_by_id(preview_id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "storage_key/1" do
    test "returns the storage key for a preview" do
      # Given
      app_build = %{id: "app-build-id"}
      account_handle = "account-handle"
      project_handle = "project-handle"

      # When
      result =
        AppBuilds.storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          app_build_id: app_build.id
        })

      # Then
      assert result == "#{account_handle}/#{project_handle}/previews/#{app_build.id}.zip"
    end

    test "returns the storage key for a preview icon with downcased account and project handles" do
      # Given
      app_build = %{id: "app-build-id"}
      account_handle = "Account"
      project_handle = "Project"

      # When
      result =
        AppBuilds.storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          app_build_id: app_build.id
        })

      # Then
      assert result == "account/project/previews/#{app_build.id}.zip"
    end
  end

  describe "icon_storage_key/1" do
    test "returns the storage key for a preview icon" do
      # Given
      preview = %{id: "app-build-group-id"}
      account_handle = "account-handle"
      project_handle = "project-handle"

      # When
      result =
        AppBuilds.icon_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview.id
        })

      # Then
      assert result == "#{account_handle}/#{project_handle}/previews/#{preview.id}/icon.png"
    end

    test "returns the storage key for a preview icon with downcased account and project handles" do
      # Given
      preview = %{id: "app-build-group-id"}
      account_handle = "AccountHandle"
      project_handle = "ProjectHandle"

      # When
      result =
        AppBuilds.icon_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview.id
        })

      # Then
      assert result == "accounthandle/projecthandle/previews/#{preview.id}/icon.png"
    end
  end

  describe "supported_platforms_case_values/1" do
    test "returns the supported platform case values" do
      # Given
      preview = %Preview{supported_platforms: [:ios, :macos]}

      # When
      result = AppBuilds.supported_platforms_case_values(preview)

      # Then
      assert result == ["iOS", "macOS"]
    end

    test "returns an empty list when supported platforms are nil" do
      # Given
      preview = %Preview{supported_platforms: nil}

      # When
      result = AppBuilds.supported_platforms_case_values(preview)

      # Then
      assert result == []
    end

    test "returns an empty list when supported platforms are empty" do
      # Given
      preview = %Preview{supported_platforms: []}

      # When
      result = AppBuilds.supported_platforms_case_values(preview)

      # Then
      assert result == []
    end
  end

  describe "latest_preview/1" do
    test "returns latest preview" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App Two",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      # When
      got = AppBuilds.latest_preview(project)

      # Then
      assert got.git_branch == "main"
      assert got.project_id == project.id
      assert got.display_name in ["App", "App Two"]
    end

    test "returns nil when no latest preview exists" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        AppBuildsFixtures.app_build_fixture(
          project: project,
          display_name: "App",
          git_branch: "other"
        )

      # When
      got = AppBuilds.latest_preview(project)

      # Then
      assert got == nil
    end

    test "returns latest preview for specified git_branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_main =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Main App",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      preview_feature =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Feature App",
          git_branch: "feature/test",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      # When
      got = AppBuilds.latest_preview(project, git_branch: "feature/test")

      # Then
      assert got.id == preview_feature.id
      assert got.git_branch == "feature/test"
      assert got.display_name == "Feature App"
    end

    test "returns latest preview when git_branch matches default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_older =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Older App",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      preview_newer =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Newer App",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      # When
      got = AppBuilds.latest_preview(project, git_branch: project.default_branch)

      # Then
      assert got.id == preview_newer.id
      assert got.git_branch == "main"
      assert got.display_name == "Newer App"
    end

    test "returns any preview when git_branch is nil" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Main App",
          git_branch: "feature"
        )

      # When
      got = AppBuilds.latest_preview(project, git_branch: nil)

      # Then
      assert got.id == preview.id
    end

    test "returns nil when no previews exist for specified git_branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_main =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Main App",
          git_branch: "main"
        )

      # When
      got = AppBuilds.latest_preview(project, git_branch: "nonexistent-branch")

      # Then
      assert got == nil
    end
  end

  describe "list_previews/1" do
    test "returns previews" do
      # Given
      project = ProjectsFixtures.project_fixture()
      project_two = ProjectsFixtures.project_fixture()

      _preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App One",
          bundle_identifier: "dev.tuist.app1"
        )

      AppBuildsFixtures.preview_fixture(
        project: project_two,
        display_name: "App Two",
        bundle_identifier: "dev.tuist.app2"
      )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App Two",
          bundle_identifier: "dev.tuist.app3"
        )

      _preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App Three",
          bundle_identifier: "dev.tuist.app4"
        )

      _preview_four =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App Four",
          bundle_identifier: "dev.tuist.app5"
        )

      _preview_five =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App Five",
          bundle_identifier: "dev.tuist.app6"
        )

      # When - Get all previews for the project (simplified test)
      {got_previews, _meta} =
        AppBuilds.list_previews(%{
          # Get more than enough
          first: 10,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:inserted_at],
          order_directions: [:desc]
        })

      # Then
      assert length(got_previews) == 5

      all_names = got_previews |> Enum.map(& &1.display_name) |> Enum.sort()
      assert all_names == ["App Five", "App Four", "App One", "App Three", "App Two"]
    end

    test "returns previews with filtered supported_platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          supported_platforms: [:ios, :watchos],
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          supported_platforms: [:macos, :watchos],
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      # When
      {got_previews_page, _got_meta_page} =
        AppBuilds.list_previews(
          %{
            first: 20,
            filters: [%{field: :project_id, op: :==, value: project.id}],
            order_by: [:inserted_at],
            order_directions: [:desc]
          },
          supported_platforms: [:ios, :visionos]
        )

      # Then
      assert Enum.map(got_previews_page, & &1.id) == [
               preview_one.id
             ]
    end

    test "returns previews with distinct bundle identifiers" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        AppBuildsFixtures.app_build_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      _preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-two",
          inserted_at: ~U[2021-01-01 03:00:00Z]
        )

      # When
      {got_previews_page, _got_meta_page} =
        AppBuilds.list_previews(
          %{
            first: 20,
            filters: [%{field: :project_id, op: :==, value: project.id}],
            order_by: [:inserted_at],
            order_directions: [:desc]
          },
          distinct: [:bundle_identifier]
        )

      # Then
      bundle_identifiers = got_previews_page |> Enum.map(& &1.bundle_identifier) |> Enum.sort()
      assert bundle_identifiers == ["com.example.app-one", "com.example.app-two"]
      assert length(got_previews_page) == 2
    end
  end

  describe "latest_previews/1" do
    test "returns latest previews with distinct bundle identifiers" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      _preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-two",
          display_name: "App Two",
          inserted_at: ~U[2021-01-01 03:00:00Z]
        )

      different_project = ProjectsFixtures.project_fixture()

      _preview_different_project =
        AppBuildsFixtures.preview_fixture(
          project: different_project,
          bundle_identifier: "com.example.other-app",
          display_name: "Other App",
          inserted_at: ~U[2021-01-01 04:00:00Z]
        )

      # When
      previews = AppBuilds.latest_previews_with_distinct_bundle_ids(project)

      # Then
      bundle_identifiers = previews |> Enum.map(& &1.bundle_identifier) |> Enum.sort()
      assert bundle_identifiers == ["com.example.app-one", "com.example.app-two"]
      assert length(previews) == 2
    end

    test "returns latest previews with distinct bundle identifiers when a preview is available from a default and non-default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          git_branch: "feature",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      # When
      previews = AppBuilds.latest_previews_with_distinct_bundle_ids(project)

      # Then
      bundle_identifiers = previews |> Enum.map(& &1.bundle_identifier) |> Enum.sort()
      assert bundle_identifiers == ["com.example.app-one"]
      assert length(previews) == 1
    end

    test "returns empty list when project has no previews" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      previews = AppBuilds.latest_previews_with_distinct_bundle_ids(project)

      # Then
      assert previews == []
    end

    test "returns previews from any branch when no previews exist on default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_feature_branch =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          git_branch: "feature/new-feature",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      _preview_develop_branch =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-two",
          display_name: "App Two",
          git_branch: "develop",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      # When
      previews = AppBuilds.latest_previews_with_distinct_bundle_ids(project)

      # Then
      assert length(previews) == 2
    end

    test "returns only previews from default branch when previews exist on default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_main_branch =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      _preview_feature_branch =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-two",
          display_name: "App Two",
          git_branch: "feature/new-feature",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      _preview_main_branch_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-three",
          display_name: "App Three",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 03:00:00Z]
        )

      # When
      previews = AppBuilds.latest_previews_with_distinct_bundle_ids(project)

      # Then
      assert length(previews) == 2
      bundle_identifiers = previews |> Enum.map(& &1.bundle_identifier) |> Enum.sort()
      assert bundle_identifiers == ["com.example.app-one", "com.example.app-three"]
      git_branches = previews |> Enum.map(& &1.git_branch) |> Enum.uniq()
      assert git_branches == ["main"]
    end
  end

  describe "app_build_by_id/2" do
    test "returns an app build by id" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview, project: project)

      # When
      {:ok, result} = AppBuilds.app_build_by_id(app_build.id)

      # Then
      assert result.id == app_build.id
    end

    test "returns an app build by id with preloaded associations" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      # When
      {:ok, result} = AppBuilds.app_build_by_id(app_build.id, preload: [:preview])

      # Then
      assert result.id == app_build.id
      assert result.preview.id == preview.id
    end

    test "returns an error when the id is invalid" do
      # Given
      invalid_id = "invalid-id"

      # When
      {:error, result} = AppBuilds.app_build_by_id(invalid_id)

      # Then
      assert result == "The provided app build identifier invalid-id doesn't have a valid format."
    end

    test "returns not_found error when the app build is not found" do
      # Given
      app_build_id = UUIDv7.generate()

      # When
      result = AppBuilds.app_build_by_id(app_build_id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "create_app_build/1" do
    test "creates an app build with all required attributes" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      attrs = %{
        preview_id: preview.id,
        type: :app_bundle,
        built_by_account_id: project.account.id,
        supported_platforms: [:ios, :macos]
      }

      # When
      app_build = AppBuilds.create_app_build(attrs)

      # Then
      assert app_build.preview_id == preview.id
      assert app_build.type == :app_bundle
      assert app_build.supported_platforms == [:ios, :macos]
    end

    test "creates an ipa type app build" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      attrs = %{
        preview_id: preview.id,
        type: :ipa,
        built_by_account_id: project.account.id,
        supported_platforms: [:ios]
      }

      # When
      app_build = AppBuilds.create_app_build(attrs)

      # Then
      assert app_build.type == :ipa
    end
  end

  describe "update_preview_with_app_build/2" do
    test "merges supported platforms and keeps private visibility for app_bundle type" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          supported_platforms: [:ios],
          visibility: :private
        )

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          type: :app_bundle,
          supported_platforms: [:macos, :watchos]
        )

      # When
      updated_preview = AppBuilds.update_preview_with_app_build(preview.id, app_build)

      # Then
      assert Enum.sort(updated_preview.supported_platforms) == [:ios, :macos, :watchos]
      assert updated_preview.visibility == :private
    end

    test "keeps visibility to private for ipa type and merges platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          supported_platforms: [:ios],
          visibility: :private
        )

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          type: :ipa,
          supported_platforms: [:ios, :watchos]
        )

      # When
      updated_preview = AppBuilds.update_preview_with_app_build(preview.id, app_build)

      # Then
      assert Enum.sort(updated_preview.supported_platforms) == [:ios, :watchos]
      assert updated_preview.visibility == :private
    end

    test "removes duplicate platforms when merging" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          supported_platforms: [:ios, :macos],
          visibility: :private
        )

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          type: :app_bundle,
          supported_platforms: [:ios, :watchos]
        )

      # When
      updated_preview = AppBuilds.update_preview_with_app_build(preview.id, app_build)

      # Then
      unique_platforms = Enum.sort(updated_preview.supported_platforms)
      assert unique_platforms == [:ios, :macos, :watchos]
      assert length(unique_platforms) == 3
    end
  end

  describe "platform_string/1" do
    test "returns correct string for ios platform" do
      assert AppBuilds.platform_string(:ios) == "iOS"
    end

    test "returns correct string for ios_simulator platform" do
      assert AppBuilds.platform_string(:ios_simulator) == "iOS Simulator"
    end

    test "returns correct string for tvos platform" do
      assert AppBuilds.platform_string(:tvos) == "tvOS"
    end

    test "returns correct string for tvos_simulator platform" do
      assert AppBuilds.platform_string(:tvos_simulator) == "tvOS Simulator"
    end

    test "returns correct string for watchos platform" do
      assert AppBuilds.platform_string(:watchos) == "watchOS"
    end

    test "returns correct string for watchos_simulator platform" do
      assert AppBuilds.platform_string(:watchos_simulator) == "watchOS Simulator"
    end

    test "returns correct string for visionos platform" do
      assert AppBuilds.platform_string(:visionos) == "visionOS"
    end

    test "returns correct string for visionos_simulator platform" do
      assert AppBuilds.platform_string(:visionos_simulator) == "visionOS Simulator"
    end

    test "returns correct string for macos platform" do
      assert AppBuilds.platform_string(:macos) == "macOS"
    end
  end

  describe "delete_preview!/1" do
    test "deletes a preview successfully" do
      # Given
      preview = AppBuildsFixtures.preview_fixture()

      # When
      AppBuilds.delete_preview!(preview)

      # Then
      assert Repo.get(Preview, preview.id) == nil
    end
  end

  describe "latest_ipa_app_build_for_preview/1" do
    test "returns the latest ipa app build for a preview" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      # Create app builds with different types and times
      _app_bundle =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          type: :app_bundle
        )

      _ipa_build_1 =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          type: :ipa
        )

      _ipa_build_2 =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          type: :ipa
        )

      # Preload app_builds for the preview
      preview_with_builds = Repo.preload(preview, :app_builds)

      # When
      result = AppBuilds.latest_ipa_app_build_for_preview(preview_with_builds)

      # Then
      # Should return an ipa build (not the app bundle)
      assert result.type == :ipa
      # Should be one of our IPA builds
      assert result.id
    end

    test "returns nil when preview has no ipa app builds" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      _app_bundle =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          type: :app_bundle
        )

      # Preload app_builds for the preview
      preview_with_builds = Repo.preload(preview, :app_builds)

      # When
      result = AppBuilds.latest_ipa_app_build_for_preview(preview_with_builds)

      # Then
      assert result == nil
    end

    test "returns nil when preview has no app builds" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      # Preload app_builds for the preview
      preview_with_builds = Repo.preload(preview, :app_builds)

      # When
      result = AppBuilds.latest_ipa_app_build_for_preview(preview_with_builds)

      # Then
      assert result == nil
    end

    test "returns the only ipa build when there's only one" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      ipa_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          type: :ipa
        )

      # Preload app_builds for the preview
      preview_with_builds = Repo.preload(preview, :app_builds)

      # When
      result = AppBuilds.latest_ipa_app_build_for_preview(preview_with_builds)

      # Then
      assert result.id == ipa_build.id
    end
  end

  describe "latest_app_build/3" do
    test "returns the latest app build for a given git ref and project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_ref: "refs/heads/feature"
        )

      _app_build_1 =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios],
          inserted_at: ~U[2021-01-01 01:30:00Z]
        )

      app_build_2 =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:macos],
          inserted_at: ~U[2021-01-01 02:30:00Z]
        )

      # When
      result = AppBuilds.latest_app_build("refs/heads/feature", project)

      # Then
      assert result.id == app_build_2.id
    end

    test "returns the latest app build with the specified supported platform" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_ref: "refs/heads/main",
          display_name: "App"
        )

      _app_build_ios =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios],
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      app_build_macos =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:macos],
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      # When
      result = AppBuilds.latest_app_build("refs/heads/main", project, supported_platform: :macos)

      # Then
      assert result.id == app_build_macos.id
    end

    test "returns nil when no previews exist for the git ref" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _other_preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_ref: "refs/heads/other"
        )

      # When
      result = AppBuilds.latest_app_build("refs/heads/nonexistent", project)

      # Then
      assert result == nil
    end

    test "returns nil when no app builds exist for matching previews" do
      # Given
      project = ProjectsFixtures.project_fixture()

      AppBuildsFixtures.preview_fixture(
        project: project,
        git_ref: "refs/heads/main"
      )

      # When
      result = AppBuilds.latest_app_build("refs/heads/main", project)

      # Then
      assert result == nil
    end

    test "returns nil when no app builds match the specified supported platform" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_ref: "refs/heads/main"
        )

      _app_build_ios =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios]
        )

      # When
      result = AppBuilds.latest_app_build("refs/heads/main", project, supported_platform: :macos)

      # Then
      assert result == nil
    end

    test "finds app build with specific platform among multiple platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_ref: "refs/heads/main"
        )

      app_build_multi_platform =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios, :macos, :watchos]
        )

      # When
      result = AppBuilds.latest_app_build("refs/heads/main", project, supported_platform: :macos)

      # Then
      assert result.id == app_build_multi_platform.id
    end
  end
end
