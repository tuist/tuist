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
    assert has_element?(editor, "[data-pane='source'] .noora-card__section #note-content[aria-label='Markdown']")
    assert has_element?(editor, "[data-pane='preview'] .noora-card__section #note-preview[data-part='note-body']")

    render_change(editor, "preview", %{
      "note" => %{"content" => "# A new note\n\n**Previewed** content."}
    })

    assert has_element?(editor, "#note-preview h2", "A new note")
    refute has_element?(editor, "#note-preview h1")
    assert has_element?(editor, "#note-preview strong", "Previewed")

    render_submit(editor, "save", %{
      "note" => %{"content" => "# A new note\n\nSaved content."}
    })

    assert [%{title: "A new note"}] = Notes.list_notes(query: "A new note")
  end

  test "previews Markdown using Noora tables, alerts, and heading typography", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/library/notes/new")

    render_change(view, "preview", %{
      "note" => %{
        "content" => """
        # Financing plan

        ## Programs

        | Program | Amount |
        | --- | --- |
        | **Berlin Start** | EUR 5k |

        > [!WARNING]
        > Verify the **terms** before applying.

        ```elixir
        :ok
        ```
        """
      }
    })

    assert has_element?(view, "#note-preview h2", "Financing plan")
    assert has_element?(view, "#note-preview h3", "Programs")
    assert has_element?(view, "#note-preview .noora-table table th", "Program")
    assert has_element?(view, "#note-preview table td strong", "Berlin Start")

    assert has_element?(
             view,
             "#note-preview .noora-alert[data-status='warning'] [data-part='description'] strong",
             "terms"
           )

    assert has_element?(view, "#note-preview pre code", ":ok")

    render_change(view, "preview", %{
      "note" => %{"content" => "# Revised plan\n\nA simpler note."}
    })

    assert has_element?(view, "#note-preview h2", "Revised plan")
    refute has_element?(view, "#note-preview table, #note-preview .noora-alert, #note-preview pre")
  end

  test "existing notes use the same sanitized Markdown preview", %{conn: conn} do
    {conn, user} = log_in_user(conn)

    {:ok, note} =
      Notes.create_note(
        %{
          content: """
          # Shared plan

          | Program | Amount |
          | --- | --- |
          | Berlin Start | EUR 5k |

          <script>alert('unsafe')</script>

          [Unsafe link](javascript:alert%281%29)
          """
        },
        user
      )

    {:ok, view, _html} = live(conn, ~p"/library/notes/#{note.id}")

    assert has_element?(view, "#note-preview[data-part='note-body'] h2", "Shared plan")
    assert has_element?(view, "#note-preview .noora-table table td", "Berlin Start")
    refute has_element?(view, "#note-preview script, #note-preview a[href^='javascript:']")

    view
    |> form("#note-form", note: %{content: "# Shared plan\n\nUpdated **context**."})
    |> render_submit()

    assert Notes.get_note(note.id).content == "# Shared plan\n\nUpdated **context**."
    assert has_element?(view, "#note-preview strong", "context")
    refute has_element?(view, "#note-preview table")
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
