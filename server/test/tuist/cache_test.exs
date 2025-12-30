defmodule Tuist.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Cache
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    {:ok, project: project}
  end

  describe "create_entry/1" do
    test "creates a cache entry", %{
      project: project
    } do
      # Given
      cas_id = "some_cas_id"
      value = "some_value"

      attrs = %{
        cas_id: cas_id,
        value: value,
        project_id: project.id
      }

      # When
      result = Cache.create_entry(attrs)

      # Then
      assert {:ok, entry} = result
      assert entry.cas_id == cas_id
      assert entry.value == value
      assert entry.project_id == project.id
    end
  end

  describe "get_entries_by_cas_id_and_project_id/2" do
    test "returns entries matching cas_id and project_id", %{project: project} do
      # Given
      cas_id = "matching_cas_id"
      project_id = project.id

      # Create some entries
      {:ok, _entry1} =
        Cache.create_entry(%{
          cas_id: cas_id,
          value: "value1",
          project_id: project_id
        })

      {:ok, _entry2} =
        Cache.create_entry(%{
          cas_id: cas_id,
          value: "value2",
          project_id: project_id
        })

      {:ok, _entry3} =
        Cache.create_entry(%{
          cas_id: "different_cas_id",
          value: "value3",
          project_id: project_id
        })

      # When
      result = Cache.get_entries_by_cas_id_and_project_id(cas_id, project_id)

      # Then
      assert Enum.map(result, & &1.cas_id) == [cas_id, cas_id]
      assert Enum.map(result, & &1.cas_id) == [cas_id, cas_id]
      assert result |> Enum.map(& &1.value) |> Enum.sort() == ["value1", "value2"]
    end

    test "returns empty list when no entries match", %{project: project} do
      # Given
      cas_id = "non_existent_cas_id"
      project_id = project.id

      # When
      result = Cache.get_entries_by_cas_id_and_project_id(cas_id, project_id)

      # Then
      assert result == []
    end
  end

  describe "delete_entries_by_project_id/1" do
    test "deletes all entries for a given project", %{project: project} do
      # Given
      project_id = project.id
      other_project = ProjectsFixtures.project_fixture()
      other_project_id = other_project.id

      # Create entries for the target project
      {:ok, _entry1} =
        Cache.create_entry(%{
          cas_id: "cas_id_1",
          value: "value1",
          project_id: project_id
        })

      {:ok, _entry2} =
        Cache.create_entry(%{
          cas_id: "cas_id_2",
          value: "value2",
          project_id: project_id
        })

      # Create entries for another project (should not be deleted)
      {:ok, _entry3} =
        Cache.create_entry(%{
          cas_id: "cas_id_3",
          value: "value3",
          project_id: other_project_id
        })

      assert length(Cache.get_entries_by_cas_id_and_project_id("cas_id_1", project_id)) == 1
      assert length(Cache.get_entries_by_cas_id_and_project_id("cas_id_2", project_id)) == 1
      assert length(Cache.get_entries_by_cas_id_and_project_id("cas_id_3", other_project_id)) == 1

      # When
      Cache.delete_entries_by_project_id(project_id)

      # Then
      assert Cache.get_entries_by_cas_id_and_project_id("cas_id_1", project_id) == []
      assert Cache.get_entries_by_cas_id_and_project_id("cas_id_2", project_id) == []
      assert length(Cache.get_entries_by_cas_id_and_project_id("cas_id_3", other_project_id)) == 1
    end

    test "returns 0 when no entries exist for the project", %{project: project} do
      # Given
      project_id = project.id

      # When
      result = Cache.delete_entries_by_project_id(project_id)

      # Then
      assert result == {0, nil}
    end
  end
end
