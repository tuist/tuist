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
end
