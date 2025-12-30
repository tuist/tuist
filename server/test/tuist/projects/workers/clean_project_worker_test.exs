defmodule Tuist.Projects.Workers.CleanProjectWorkerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Cache
  alias Tuist.CacheActionItems
  alias Tuist.Projects
  alias Tuist.Projects.Workers.CleanProjectWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  describe "perform" do
    test "deletes binaries, selective testing, cache action items, and cache entries", %{project: project} do
      # Given
      project_id = project.id
      project_slug = "#{project.account.name}/#{project.name}"

      expect(CacheActionItems, :delete_all_action_items, 1, fn %{project: %{id: ^project_id}} ->
        :ok
      end)

      cas_objects = "#{project_slug}/cas"
      binaries_objects = "#{project_slug}/builds"
      tests_objects = "#{project_slug}/tests"
      expect(Storage, :delete_all_objects, fn ^cas_objects, _actor -> :ok end)
      expect(Storage, :delete_all_objects, fn ^binaries_objects, _actor -> :ok end)
      expect(Storage, :delete_all_objects, fn ^tests_objects, _actor -> :ok end)

      expect(Cache, :delete_entries_by_project_id, 1, fn ^project_id ->
        {5, nil}
      end)

      # When
      result = CleanProjectWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})

      # Then
      assert result == :ok
    end

    test "returns :ok when the project doesn't exist" do
      # Given
      non_existent_project_id = UUIDv7.generate()

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
