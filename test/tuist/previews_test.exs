defmodule Tuist.PreviewsTest do
  alias Tuist.PreviewsFixtures
  alias Tuist.CommandEventsFixtures
  alias Tuist.Previews.Preview
  alias Tuist.Previews
  alias Tuist.ProjectsFixtures
  use Tuist.DataCase, async: true

  describe "create_preview/1" do
    test "creates a bundle preview" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      preview =
        Previews.create_preview(%{
          project: project,
          type: :app_bundle,
          display_name: "App",
          version: nil,
          bundle_identifier: nil
        })

      # Then
      assert Repo.all(Preview) == [preview]
    end

    test "creates an archive preview" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      preview =
        Previews.create_preview(%{
          project: project,
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        })

      # Then
      assert Repo.all(Preview) == [preview]
    end
  end

  describe "get_preview_by_id/1" do
    test "returns a preview by id" do
      # Given
      preview =
        Previews.create_preview(%{
          project: ProjectsFixtures.project_fixture(),
          type: :app_bundle,
          display_name: "App",
          version: nil,
          bundle_identifier: nil
        })

      # When
      result = Previews.get_preview_by_id(preview.id)

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
      result = Previews.get_preview_by_id(preview.id, preload: [:command_event])

      # Then
      assert result.command_event.id == command_event.id
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
  end
end
