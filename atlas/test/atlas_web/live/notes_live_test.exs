defmodule AtlasWeb.NotesLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Notes

  test "employees can browse and create notes with a Markdown preview", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{role: :employee})
    {:ok, note} = Notes.create_note(%{content: "# Existing note\n\nShared context."}, user)

    {:ok, view, _html} = live(conn, ~p"/library/notes")

    assert has_element?(view, "#notes")
    assert has_element?(view, "#notes-new-button")
    assert has_element?(view, "#notes-filters-dropdown")
    assert has_element?(view, "#notes-table a[href=\"/library/notes/#{note.id}\"]", "Existing note")

    {:ok, editor, _html} = live(conn, ~p"/library/notes/new")
    assert has_element?(editor, "#note-form")
    assert has_element?(editor, "#note-content[maxlength='50000']")
    assert has_element?(editor, "#note-content[phx-debounce='300']")
    assert has_element?(editor, "#note-preview")

    render_change(editor, "preview", %{
      "note" => %{"content" => "# A new note\n\n**Previewed** content."}
    })

    assert has_element?(editor, "#note-preview h1", "A new note")
    assert has_element?(editor, "#note-preview strong", "Previewed")

    render_submit(editor, "save", %{
      "note" => %{"content" => "# A new note\n\nSaved content."}
    })

    assert [%{title: "A new note"}] = Notes.list_notes(query: "A new note")
  end

  test "searches notes while typing", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, matching} = Notes.create_note(%{content: "# Searchable note\n\nMatches the query."}, user)
    {:ok, other} = Notes.create_note(%{content: "# Other note\n\nDifferent content."}, user)

    {:ok, view, _html} = live(conn, ~p"/library/notes")

    render_change(view, "search", %{"search" => %{"query" => "Searchable"}})

    assert has_element?(view, "#notes-table a[href=\"/library/notes/#{matching.id}\"]")
    refute has_element?(view, "#notes-table a[href=\"/library/notes/#{other.id}\"]")

    render_change(view, "search", %{"search" => %{"query" => "does-not-match"}})
    assert has_element?(view, "#notes-table", "No notes")

    render_change(view, "search", %{"search" => %{"query" => ""}})
    assert has_element?(view, "#notes-table a[href=\"/library/notes/#{matching.id}\"]")
    assert has_element?(view, "#notes-table a[href=\"/library/notes/#{other.id}\"]")
    refute has_element?(view, "#notes-table", "Create a Markdown note to make it searchable here.")
  end

  test "rejects a note without an h1", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/library/notes/new")

    render_submit(view, "save", %{"note" => %{"content" => "Missing title"}})

    assert has_element?(view, "#note-form")
    assert Notes.list_notes(query: "Missing title") == []
  end
end
