defmodule Atlas.Engineering.PostmortemsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Engineering.Postmortems
  alias Atlas.Engineering.Postmortems.ActionItem
  alias Atlas.Engineering.Postmortems.Embedding
  alias Atlas.Repo
  alias Atlas.Users.User

  defp user(email \\ nil) do
    email = email || "postmortems-#{System.unique_integer([:positive])}@tuist.dev"

    %User{}
    |> User.changeset(%{email: email, name: "Postmortem Author"})
    |> Repo.insert!()
  end

  test "publishes a Markdown postmortem and uses its first line as the title" do
    assert {:ok, postmortem} =
             Postmortems.publish_postmortem(
               %{"body" => "# Database incident\n\nThe database was unavailable."},
               user()
             )

    assert Postmortems.title(postmortem) == "Database incident"
    assert [listed] = Postmortems.list_postmortems()
    assert listed.id == postmortem.id
    assert listed.number == postmortem.number
  end

  test "assigns increasing public numbers" do
    {:ok, first} =
      Postmortems.publish_postmortem(
        %{"body" => "# First incident\n\nThe first incident."},
        user()
      )

    {:ok, second} =
      Postmortems.publish_postmortem(
        %{"body" => "# Second incident\n\nThe second incident."},
        user()
      )

    assert second.number > first.number
  end

  test "publish returns :unauthorized for a non-user" do
    assert {:error, :unauthorized} =
             Postmortems.publish_postmortem(%{"body" => "# x\n\nyy"}, nil)
  end

  test "persists an embedding once for unchanged content" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Delivery delay\n\nA worker backlog delayed customer notifications."},
        owner
      )

    content_hash = :crypto.hash(:sha256, postmortem.body) |> Base.encode16(case: :lower)

    embed = fn _text ->
      send(self(), :embedded)
      {:ok, [0.8, 0.2]}
    end

    assert {:ok, %Embedding{status: :indexed}} =
             Postmortems.index_postmortem(postmortem.id, content_hash, embed: embed)

    assert_received :embedded

    assert {:ok, %Embedding{status: :indexed}} =
             Postmortems.index_postmortem(postmortem.id, content_hash, embed: embed)

    refute_received :embedded

    assert %Embedding{embedding: [0.8, 0.2]} =
             Repo.get_by(Embedding, postmortem_id: postmortem.id)
  end

  test "updates a postmortem" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(%{"body" => "# Original\n\nStory."}, owner)

    assert {:ok, updated} =
             Postmortems.update_postmortem(postmortem, %{"body" => "# New title\n\nStory."}, owner)

    assert Postmortems.title(updated) == "New title"
  end

  test "creates, toggles and deletes an action item" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Title\n\nSome body text long enough to satisfy the validation."},
        owner
      )

    assert {:ok, %ActionItem{} = action_item} =
             Postmortems.create_action_item(
               postmortem,
               %{"title" => "Follow up with vendor", "priority" => "high"},
               owner
             )

    assert action_item.priority == :high
    assert is_nil(action_item.completed_at)

    assert {:ok, toggled} = Postmortems.toggle_action_item(postmortem, action_item, owner)
    refute is_nil(toggled.completed_at)

    assert {:ok, _deleted} = Postmortems.delete_action_item(postmortem, toggled, owner)
    assert is_nil(Repo.get(ActionItem, action_item.id))
  end

  test "deletes a postmortem" do
    owner = user()
    {:ok, postmortem} = Postmortems.publish_postmortem(%{"body" => "# gone\n\nbye"}, owner)

    assert {:ok, _} = Postmortems.delete_postmortem(postmortem, owner)
    assert is_nil(Postmortems.get_postmortem(postmortem.id))
  end

  test "ensure_share_token lazily generates and persists a UUID" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(%{"body" => "# share\n\nlink me"}, owner)

    assert is_nil(postmortem.share_token)

    assert {:ok, %{share_token: token}} = Postmortems.ensure_share_token(postmortem)
    assert is_binary(token)

    reloaded = Postmortems.get_postmortem!(postmortem.id)
    assert reloaded.share_token == token

    assert {:ok, %{share_token: ^token}} = Postmortems.ensure_share_token(reloaded)
    assert Postmortems.get_postmortem_by_share_token(token).id == postmortem.id
  end
end
