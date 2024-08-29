defmodule Tuist.PreviewsTest do
  alias Tuist.Previews.Preview
  alias Tuist.Previews
  alias Tuist.ProjectsFixtures
  use Tuist.DataCase, async: true

  describe "create_preview/1" do
    test "creates a build" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      preview = Previews.create_preview(%{project: project, display_name: "App"})

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
          display_name: "App"
        })

      # When
      result = Previews.get_preview_by_id(preview.id)

      # Then
      assert result == preview
    end
  end
end
