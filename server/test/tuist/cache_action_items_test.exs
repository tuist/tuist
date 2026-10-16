defmodule Tuist.CacheActionItemsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.CacheActionItems
  alias Tuist.Projects.Project
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  setup do
    project = ProjectsFixtures.project_fixture()
    {:ok, project: project}
  end

  describe "create_cache_action_item/1" do
    test "creates a cache action item with valid attributes", %{project: project} do
      # Given
      first_cache_action_item = %{
        id: UUIDv7.generate(),
        hash: UUIDv7.generate(),
        project_id: project.id,
        inserted_at: DateTime.utc_now(:second),
        updated_at: DateTime.utc_now(:second)
      }

      second_cache_action_item = %{
        id: UUIDv7.generate(),
        hash: UUIDv7.generate(),
        project_id: project.id,
        inserted_at: DateTime.utc_now(:second),
        updated_at: DateTime.utc_now(:second)
      }

      # When
      {2, _} =
        CacheActionItems.create_cache_action_items([
          first_cache_action_item,
          second_cache_action_item
        ])

      # Then
      assert CacheActionItems.get_cache_action_item(%{
               project: project,
               hash: first_cache_action_item.hash
             })

      assert CacheActionItems.get_cache_action_item(%{
               project: project,
               hash: second_cache_action_item.hash
             })
    end

    test "handles the creation when a cache_action_item with the same hash exists", %{
      project: project
    } do
      # Given
      cache_action_item = %{
        id: UUIDv7.generate(),
        hash: UUIDv7.generate(),
        project_id: project.id,
        inserted_at: DateTime.utc_now(:second),
        updated_at: DateTime.utc_now(:second)
      }

      # When
      {1, _} =
        CacheActionItems.create_cache_action_items([
          cache_action_item
        ])

      {0, _} =
        CacheActionItems.create_cache_action_items([
          cache_action_item
        ])

      # Then
      assert CacheActionItems.get_cache_action_item(%{
               project: project,
               hash: cache_action_item.hash
             })
    end
  end

  describe "create_cache_action_items/1" do
    test "inserts rows in project and hash order", %{project: first} do
      second = ProjectsFixtures.project_fixture()
      now = DateTime.utc_now(:second)

      rows =
        Enum.map(
          [{second.id, "hash-b"}, {second.id, "hash-a"}, {first.id, "hash-b"}, {first.id, "hash-a"}],
          fn {project_id, hash} ->
            %{id: UUIDv7.generate(), project_id: project_id, hash: hash, inserted_at: now, updated_at: now}
          end
        )

      test_pid = self()

      stub(Repo, :insert_all, fn schema, rows, opts ->
        send(test_pid, {:insert_all, schema, rows})
        Mimic.call_original(Repo, :insert_all, [schema, rows, opts])
      end)

      assert {4, _} = CacheActionItems.create_cache_action_items(rows)
      assert_received {:insert_all, CacheActionItems.CacheActionItem, inserted_rows}

      assert Enum.map(inserted_rows, &{&1.project_id, &1.hash}) == [
               {first.id, "hash-a"},
               {first.id, "hash-b"},
               {second.id, "hash-a"},
               {second.id, "hash-b"}
             ]

      for project <- [first, second], hash <- ["hash-a", "hash-b"] do
        assert CacheActionItems.get_cache_action_item(%{project: project, hash: hash})
      end
    end

    test "creates a cache action item with valid attributes", %{project: project} do
      # When
      cache_action_item =
        CacheActionItems.create_cache_action_item(%{
          hash: "somehash",
          project: project
        })

      # Then
      assert cache_action_item.hash == "somehash"
      assert cache_action_item.project_id == project.id
    end

    test "handles the creation when a cache_action_item with the same hash exists", %{
      project: project
    } do
      # Given
      CacheActionItems.create_cache_action_item(%{
        hash: "somehash",
        project: project
      })

      # When
      cache_action_item =
        CacheActionItems.create_cache_action_item(%{
          hash: "somehash",
          project: project
        })

      # # Then
      assert cache_action_item.hash == "somehash"
      assert cache_action_item.project_id == project.id
    end
  end

  describe "get_cache_action_item/1" do
    test "gets cache action item", %{project: project} do
      # Given
      cache_action_item =
        CacheActionItems.create_cache_action_item(%{
          hash: "somehash",
          project: project
        })

      # When / Then
      assert cache_action_item ==
               CacheActionItems.get_cache_action_item(%{
                 project: project,
                 hash: "somehash"
               })
    end

    test "returns nil if the cache action item does not exist" do
      # When / Then
      assert CacheActionItems.get_cache_action_item(%{
               project: %Project{id: 1},
               hash: "somehash"
             }) == nil
    end
  end

  describe "delete_all_action_items/1" do
    test "deletes all cache action items for a project", %{project: project} do
      # Given
      CacheActionItems.create_cache_action_item(%{
        hash: "hash-one",
        project: project
      })

      CacheActionItems.create_cache_action_item(%{
        hash: "hash-two",
        project: project
      })

      project_two = ProjectsFixtures.project_fixture()

      project_two_cache_action_item =
        CacheActionItems.create_cache_action_item(%{
          hash: "hash-three",
          project: project_two
        })

      # When
      CacheActionItems.delete_all_action_items(%{project: project})

      # Then
      assert Repo.all(CacheActionItems.CacheActionItem) == [project_two_cache_action_item]
    end
  end
end
