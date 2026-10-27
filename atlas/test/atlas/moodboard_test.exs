defmodule Atlas.MoodboardTest do
  use Atlas.DataCase, async: true

  import Atlas.MCP.ToolCase, only: [insert_user!: 0]

  alias Atlas.Audit.Activity
  alias Atlas.Moodboard
  alias Atlas.Repo

  test "attributes resources to their contributor and normalizes tags" do
    user = insert_user!()

    assert {:ok, resource} =
             Moodboard.create_resource(
               attrs(%{title: "  A reference  ", tags: [" Typography ", "typography", "", "Tools"]}),
               user
             )

    assert resource.title == "A reference"
    assert resource.tags == ["typography", "tools"]
    assert resource.created_by_id == user.id
    assert resource.created_by.id == user.id

    assert Repo.get_by!(Activity, target_id: resource.id).action == "moodboard_resource.created"
  end

  test "requires a title and public HTTPS links, including preview images" do
    user = insert_user!()
    assert {:error, changeset} = Moodboard.create_resource(%{}, user)
    assert %{title: ["can't be blank"], url: ["can't be blank"]} = errors_on(changeset)

    for url <- [
          "javascript:alert(1)",
          "https://localhost/a",
          "https://127.0.0.1/a",
          "https://10.0.0.1/a",
          "http://example.com",
          "https://user:pass@example.com",
          "https://example.com:bad",
          "https://example.com/ bad"
        ] do
      assert {:error, changeset} = Moodboard.create_resource(attrs(%{url: url}), user)
      assert "must be a public HTTPS URL" in errors_on(changeset).url
      assert {:error, changeset} = Moodboard.create_resource(attrs(%{image_url: url}), user)
      assert "must be a public HTTPS URL" in errors_on(changeset).image_url
    end
  end

  test "bounds fields and rejects duplicate links" do
    user = insert_user!()
    resource_attrs = attrs()
    assert {:ok, _resource} = Moodboard.create_resource(resource_attrs, user)
    assert {:error, changeset} = Moodboard.create_resource(resource_attrs, user)
    assert "has already been taken" in errors_on(changeset).url

    assert {:error, changeset} = Moodboard.create_resource(attrs(%{tags: [String.duplicate("a", 41)]}), user)
    assert errors_on(changeset).tags
    assert {:error, changeset} = Moodboard.create_resource(attrs(%{title: String.duplicate("a", 201)}), user)
    assert errors_on(changeset).title
  end

  test "optional fields can be cleared without losing other metadata" do
    user = insert_user!()

    {:ok, resource} =
      Moodboard.create_resource(
        attrs(%{description: "Context", image_url: "https://images.example/preview.png", tags: ["type"]}),
        user
      )

    assert {:ok, updated} = Moodboard.update_resource(resource.id, %{description: nil, image_url: nil, tags: []}, user)
    assert updated.description == nil
    assert updated.image_url == nil
    assert updated.tags == []
    assert updated.url == resource.url
  end

  test "searches and filters before bounded pagination" do
    user = insert_user!()
    {:ok, first} = Moodboard.create_resource(attrs(%{title: "Typography reference", tags: ["type"]}), user)

    {:ok, second} =
      Moodboard.create_resource(attrs(%{title: "Another reference", description: "Typography", tags: ["type"]}), user)

    {:ok, _unrelated} = Moodboard.create_resource(attrs(%{title: "Unrelated"}), user)

    assert {[resource], true} = Moodboard.list_resources(user, query: "Typography", tag: "type", limit: 1)
    assert {[other], false} = Moodboard.list_resources(user, query: "Typography", tag: "type", limit: 1, offset: 1)
    assert MapSet.new([resource.id, other.id]) == MapSet.new([first.id, second.id])
    assert {[], false} = Moodboard.list_resources(user, query: "%")
  end

  test "all teammates can read but only the contributor can update or delete" do
    user = insert_user!()
    teammate = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)

    assert Moodboard.get_resource(teammate, resource.id).id == resource.id
    assert {:error, :forbidden} = Moodboard.update_resource(resource.id, %{title: "Changed"}, teammate)
    assert {:error, :forbidden} = Moodboard.delete_resource(resource.id, teammate)
    assert {:ok, updated} = Moodboard.update_resource(resource.id, %{title: "Changed", image_url: nil}, user)
    assert updated.title == "Changed"
    assert {:ok, _deleted} = Moodboard.delete_resource(resource.id, user)
    assert Moodboard.get_resource(user, resource.id) == nil
  end

  test "missing IDs and unauthenticated writes fail safely" do
    user = insert_user!()
    assert Moodboard.get_resource(user, "not-a-uuid") == nil
    assert {:error, :not_found} = Moodboard.update_resource(nil, %{}, user)
    assert {:error, :not_found} = Moodboard.delete_resource(Ecto.UUID.generate(), user)
    assert {:error, :authentication_required} = Moodboard.create_resource(attrs(), nil)
    assert {:error, :authentication_required} = Moodboard.update_resource(Ecto.UUID.generate(), %{}, nil)
  end

  test "user deletion preserves shared resources without contributor identity" do
    user = insert_user!()
    teammate = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)
    Repo.delete!(user)
    assert %{created_by_id: nil, created_by: nil} = Moodboard.get_resource(teammate, resource.id)
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{title: "Design reference", url: "https://design.example/#{System.unique_integer([:positive])}"},
      overrides
    )
  end
end
