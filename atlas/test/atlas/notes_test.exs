defmodule Atlas.NotesTest do
  use Atlas.DataCase, async: true

  alias Atlas.Notes
  alias Atlas.Notes.Note
  alias Atlas.Repo
  alias Atlas.Users.User

  test "creates notes with a title derived from the first h1 and indexes them" do
    user = insert_user!()

    assert {:ok, %Note{} = note} =
             Notes.create_note(%{content: "Intro\n\n# Project Atlas\n\nThe plan."}, user)

    assert note.title == "Project Atlas"
    assert note.visibility == "authenticated"
    assert note.created_by_id == user.id
    assert Notes.get_note(note.id).created_by.id == user.id
    assert Repo.get_by(Atlas.Search.Record, source_type: "note", source_id: note.id)
  end

  test "requires an h1 heading" do
    user = insert_user!()

    assert {:error, changeset} = Notes.create_note(%{content: "No title here."}, user)
    assert "must start with an h1 heading" in errors_on(changeset).content
  end

  test "updates the title and search record when Markdown changes" do
    user = insert_user!()
    {:ok, note} = Notes.create_note(%{content: "# Original\n\nBody"}, user)

    assert {:ok, updated} = Notes.update_note(note, %{content: "# Revised\n\nNew body"})
    assert updated.title == "Revised"

    assert %{title: "Revised", body: "# Revised\n\nNew body"} =
             Repo.get_by!(Atlas.Search.Record, source_type: "note", source_id: note.id)
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      email: "notes-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Notes User"
    })
    |> Repo.insert!()
  end
end
