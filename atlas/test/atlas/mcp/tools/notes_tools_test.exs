defmodule Atlas.MCP.Tools.NotesToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.CreateNote
  alias Atlas.MCP.Tools.GetNote
  alias Atlas.MCP.Tools.SearchNotes
  alias Atlas.MCP.Tools.UpdateNote
  alias Atlas.Notes

  test "creates and retrieves a Markdown note for any authenticated user" do
    user = insert_user!()
    conn = mcp_conn(user)

    assert {:ok, %{note: %{title: "MCP note"} = note}} =
             execute_tool(CreateNote, conn, %{"content" => "# MCP note\n\nAgent content."})

    assert {:ok, %{note: %{id: note_id, content: "# MCP note\n\nAgent content."}}} =
             execute_tool(GetNote, conn, %{"note_id" => note.id})

    assert {:ok, %{note: %{title: "Updated MCP note"}}} =
             execute_tool(UpdateNote, conn, %{
               "note_id" => note_id,
               "content" => "# Updated MCP note\n\nChanged."
             })

    assert {:ok, %{results: [%{note: %{id: ^note_id}}]}} =
             execute_tool(SearchNotes, conn, %{"query" => "Changed"})

    assert Notes.get_note(note_id).title == "Updated MCP note"
  end

  test "requires an h1 heading" do
    assert {:error, message} =
             execute_tool(CreateNote, mcp_conn(insert_user!()), %{"content" => "No heading"})

    assert message =~ "must start with an h1 heading"
  end
end
