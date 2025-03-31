defmodule Tuist.PreviewsTest do
  alias TuistTestSupport.Fixtures.PreviewsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias Tuist.Previews.Preview
  alias Tuist.Previews
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  use TuistTestSupport.Cases.DataCase, async: true

  describe "create_preview/1" do
    test "creates a bundle preview" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      preview =
        PreviewsFixtures.preview_fixture(
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
        PreviewsFixtures.preview_fixture(
          project: project,
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        )

      # Then
      assert Repo.all(Preview) == [preview]
    end
  end

  describe "get_preview_by_id/1" do
    test "returns a preview by id" do
      # Given
      preview =
        PreviewsFixtures.preview_fixture(
          project: ProjectsFixtures.project_fixture(),
          type: :app_bundle,
          display_name: "App",
          version: nil,
          bundle_identifier: nil
        )

      # When
      {:ok, result} = Previews.get_preview_by_id(preview.id)

      # Then
      assert result == preview
    end

    test "returns a preview by id with preloaded command event" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview = PreviewsFixtures.preview_fixture(project: project)

      command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview.id
        )

      # When
      {:ok, result} = Previews.get_preview_by_id(preview.id, preload: [:command_event])

      # Then
      assert result.command_event.id == command_event.id
    end

    test "returns an error when the id is invalid" do
      # Given
      invalid_id = "invalid-id"

      # When
      {:error, result} = Previews.get_preview_by_id(invalid_id)

      # Then
      assert result ==
               "The provided preview ID invalid-id doesn't have a valid format."
    end

    test "returns not_found error when the preview is not found" do
      # Given
      preview_id = UUIDv7.generate()

      # When
      result = Previews.get_preview_by_id(preview_id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "get_storage_key/1" do
    test "returns the storage key for a preview" do
      # Given
      preview = %Preview{id: "preview-id"}
      account_handle = "account-handle"
      project_handle = "project-handle"

      # When
      result =
        Previews.get_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview.id
        })

      # Then
      assert result == "#{account_handle}/#{project_handle}/previews/#{preview.id}.zip"
    end

    test "returns the storage key for a preview icon with downcased account and project handles" do
      # Given
      preview = %Preview{id: "preview-id"}
      account_handle = "AccountHandle"
      project_handle = "ProjectHandle"

      # When
      result =
        Previews.get_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview.id
        })

      # Then
      assert result == "accounthandle/projecthandle/previews/#{preview.id}.zip"
    end
  end

  describe "get_icon_storage_key/1" do
    test "returns the storage key for a preview icon" do
      # Given
      preview = %Preview{id: "preview-id"}
      account_handle = "account-handle"
      project_handle = "project-handle"

      # When
      result =
        Previews.get_icon_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview.id
        })

      # Then
      assert result == "#{account_handle}/#{project_handle}/previews/#{preview.id}/icon.png"
    end

    test "returns the storage key for a preview icon with downcased account and project handles" do
      # Given
      preview = %Preview{id: "preview-id"}
      account_handle = "AccountHandle"
      project_handle = "ProjectHandle"

      # When
      result =
        Previews.get_icon_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview.id
        })

      # Then
      assert result == "accounthandle/projecthandle/previews/#{preview.id}/icon.png"
    end
  end

  describe "get_supported_platforms_case_values/1" do
    test "returns the supported platform case values" do
      # Given
      preview = %Preview{supported_platforms: [:ios, :macos]}

      # When
      result = Previews.get_supported_platforms_case_values(preview)

      # Then
      assert result == ["iOS", "macOS"]
    end

    test "returns an empty list when supported platforms are nil" do
      # Given
      preview = %Preview{supported_platforms: nil}

      # When
      result = Previews.get_supported_platforms_case_values(preview)

      # Then
      assert result == []
    end

    test "returns an empty list when supported platforms are empty" do
      # Given
      preview = %Preview{supported_platforms: []}

      # When
      result = Previews.get_supported_platforms_case_values(preview)

      # Then
      assert result == []
    end
  end

  describe "get_latest_preview/1" do
    test "returns latest preview" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "main",
          inserted_at: ~N[2021-01-01 00:00:00]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "main",
          inserted_at: ~N[2021-01-01 01:00:00]
        )

      # When
      got = Previews.get_latest_preview(project)

      # Then
      assert got.id == preview_two.id
    end

    test "returns nil when no latest preview exists" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "other"
        )

      # When
      got = Previews.get_latest_preview(project)

      # Then
      assert got == nil
    end
  end

  describe "list_previews/1" do
    test "returns previews" do
      # Given
      project = ProjectsFixtures.project_fixture()
      project_two = ProjectsFixtures.project_fixture()

      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App One",
          inserted_at: ~U[2024-03-04 01:00:00Z]
        )

      PreviewsFixtures.preview_fixture(
        project: project_two,
        display_name: "App Two",
        inserted_at: ~N[2024-03-05 02:00:00]
      )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App Two",
          inserted_at: ~U[2024-03-05 03:00:00Z]
        )

      preview_three =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App Three",
          inserted_at: ~U[2024-03-05 04:00:00Z]
        )

      preview_four =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App Four",
          inserted_at: ~U[2024-03-05 05:00:00Z]
        )

      preview_five =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App Five",
          inserted_at: ~U[2024-03-05 06:00:00Z]
        )

      # When
      {got_previews_first_page, got_meta_first_page} =
        Previews.list_previews(%{
          page: 1,
          page_size: 2,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:inserted_at],
          order_directions: [:desc]
        })

      {got_previews_second_page, got_meta_second_page} =
        Previews.list_previews(Flop.to_next_page(got_meta_first_page.flop))

      {got_previews_third_page, _meta} =
        Previews.list_previews(Flop.to_next_page(got_meta_second_page.flop))

      # Then
      assert got_previews_first_page == [preview_five, preview_four]
      assert got_previews_second_page == [preview_three, preview_two]
      assert got_previews_third_page == [preview_one]
    end

    test "returns previews with filtered supported_platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          supported_platforms: [:ios, :watchos],
          inserted_at: ~N[2021-01-01 00:00:00]
        )

      _preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          supported_platforms: [:macos, :watchos],
          inserted_at: ~N[2021-01-01 01:00:00]
        )

      # When
      {got_previews_page, _got_meta_page} =
        Previews.list_previews(
          %{
            first: 20,
            filters: [%{field: :project_id, op: :==, value: project.id}],
            order_by: [:inserted_at],
            order_directions: [:desc]
          },
          supported_platforms: [:ios, :visionos]
        )

      # Then
      assert got_previews_page |> Enum.map(& &1.id) == [
               preview_one.id
             ]
    end

    test "returns previews with distinct bundle identifiers" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      preview_three =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-two",
          inserted_at: ~U[2021-01-01 03:00:00Z]
        )

      # When
      {got_previews_page, _got_meta_page} =
        Previews.list_previews(
          %{
            first: 20,
            filters: [%{field: :project_id, op: :==, value: project.id}],
            order_by: [:inserted_at],
            order_directions: [:desc]
          },
          distinct: [:bundle_identifier]
        )

      # Then
      assert got_previews_page |> Enum.map(& &1.id) == [
               preview_three.id,
               preview_two.id
             ]

      assert got_previews_page |> Enum.map(& &1.bundle_identifier) == [
               "com.example.app-two",
               "com.example.app-one"
             ]
    end
  end

  describe "latest_previews/1" do
    test "returns latest previews with distinct bundle identifiers" do
      # Given
      project = ProjectsFixtures.project_fixture()

      _preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-one",
          display_name: "App One",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      preview_three =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.example.app-two",
          display_name: "App Two",
          inserted_at: ~U[2021-01-01 03:00:00Z]
        )

      different_project = ProjectsFixtures.project_fixture()

      _preview_different_project =
        PreviewsFixtures.preview_fixture(
          project: different_project,
          bundle_identifier: "com.example.other-app",
          display_name: "Other App",
          inserted_at: ~U[2021-01-01 04:00:00Z]
        )

      # When
      previews = Previews.latest_previews_with_distinct_bundle_ids(project)

      # Then
      assert previews |> Enum.map(& &1.id) == [preview_three.id, preview_two.id]
    end

    test "returns empty list when project has no previews" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      previews = Previews.latest_previews_with_distinct_bundle_ids(project)

      # Then
      assert previews == []
    end
  end
end
