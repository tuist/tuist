defmodule Tuist.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Cache
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    {:ok, project: project}
  end

  describe "put_key_value/3" do
    test "stores values for a key", %{project: project} do
      # Given
      cas_id = "some_cas_id"
      values = ["value1", "value2", "value3"]

      # When
      result = Cache.put_key_value(cas_id, project.id, values)

      # Then
      assert result == :ok
    end
  end

  describe "get_key_value/2" do
    test "returns values for a given key", %{project: project} do
      # Given
      cas_id = "matching_cas_id"
      project_id = project.id
      values = ["value1", "value2"]

      :ok = Cache.put_key_value(cas_id, project_id, values)

      # When
      result = Cache.get_key_value(cas_id, project_id)

      # Then
      assert result == values
    end

    test "returns empty list when no values exist", %{project: project} do
      # Given
      cas_id = "non_existent_cas_id"
      project_id = project.id

      # When
      result = Cache.get_key_value(cas_id, project_id)

      # Then
      assert result == []
    end

    test "overwrites existing values when storing", %{project: project} do
      # Given
      cas_id = "test_cas_id"
      project_id = project.id

      :ok = Cache.put_key_value(cas_id, project_id, ["old_value1", "old_value2"])
      :ok = Cache.put_key_value(cas_id, project_id, ["new_value1", "new_value2", "new_value3"])

      # When
      result = Cache.get_key_value(cas_id, project_id)

      # Then
      assert result == ["new_value1", "new_value2", "new_value3"]
    end

    test "isolates values by project_id", %{project: project} do
      # Given
      cas_id = "shared_cas_id"
      project_id = project.id
      other_project = ProjectsFixtures.project_fixture()
      other_project_id = other_project.id

      # Store different values for the same cas_id but different projects
      :ok = Cache.put_key_value(cas_id, project_id, ["project1_value"])
      :ok = Cache.put_key_value(cas_id, other_project_id, ["project2_value"])

      # When
      result1 = Cache.get_key_value(cas_id, project_id)
      result2 = Cache.get_key_value(cas_id, other_project_id)

      # Then
      assert result1 == ["project1_value"]
      assert result2 == ["project2_value"]
    end
  end
end
