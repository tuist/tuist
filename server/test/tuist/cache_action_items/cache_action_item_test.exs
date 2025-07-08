defmodule Tuist.CacheActionItems.CacheActionItemTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.CacheActionItems.CacheActionItem
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_changeset/1" do
    test "with valid attributes" do
      changeset =
        CacheActionItem.create_changeset(%CacheActionItem{}, %{
          project_id: 1,
          hash: "somehash",
          category: :tests,
          name: "name"
        })

      assert changeset.valid?
    end

    test "ensures project_id is present" do
      changeset =
        CacheActionItem.create_changeset(%CacheActionItem{}, %{
          hash: "somehash"
        })

      refute changeset.valid?

      assert %{
               project_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "ensures a hash is present" do
      changeset =
        CacheActionItem.create_changeset(%CacheActionItem{}, %{
          project_id: 1,
          category: :tests,
          name: "name"
        })

      refute changeset.valid?

      assert %{
               hash: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "ensures project_id, hash, and category are unique" do
      # Given
      cache_action_item = %CacheActionItem{}
      %{id: project_id} = ProjectsFixtures.project_fixture()

      changeset =
        CacheActionItem.create_changeset(cache_action_item, %{
          project_id: project_id,
          hash: "somehash",
          category: :tests,
          name: "name"
        })

      Repo.insert!(changeset)

      # When
      {:error, got} =
        Repo.insert(
          CacheActionItem.create_changeset(cache_action_item, %{
            project_id: project_id,
            hash: "somehash",
            category: :tests,
            name: "name"
          })
        )

      # Then
      assert "has already been taken" in errors_on(got).hash
    end
  end
end
