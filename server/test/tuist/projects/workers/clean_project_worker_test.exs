defmodule Tuist.Projects.Workers.CleanProjectWorkerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.CacheActionItems
  alias Tuist.Projects
  alias Tuist.Projects.Workers.CleanProjectWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  describe "perform" do
    test "deletes binaries, selective testing, and cache action items", %{project: project} do
      # Given
      project_id = project.id
      project_slug = "#{project.account.name}/#{project.name}"

      expect(CacheActionItems, :delete_all_action_items, 1, fn %{project: %{id: ^project_id}} ->
        :ok
      end)

      binaries_objects = "#{project_slug}/builds"
      tests_objects = "#{project_slug}/tests"
      expect(Storage, :delete_all_objects, 1, fn ^binaries_objects -> :ok end)
      expect(Storage, :delete_all_objects, 1, fn ^tests_objects -> :ok end)

      # When
      result = CleanProjectWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})

      # Then
      assert result == :ok
    end

    test "returns :ok when the project doesn't exist" do
      # Given
      non_existent_project_id = Ecto.UUID.generate()

      # Mock Projects.get_project_by_id to return nil
      expect(Projects, :get_project_by_id, fn ^non_existent_project_id -> nil end)

      # Don't expect any calls to Storage or CacheActionItems
      # as the function should return early

      # When
      result =
        CleanProjectWorker.perform(%Oban.Job{args: %{"project_id" => non_existent_project_id}})

      # Then
      assert result == :ok
    end
  end
end
