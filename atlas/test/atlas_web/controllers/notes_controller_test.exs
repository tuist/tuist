defmodule AtlasWeb.NotesControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Guardian
  alias Atlas.Notes

  test "authenticated API clients can create, search, and update notes", %{conn: conn} do
    {_session_conn, user} = log_in_user(conn)
    api_conn = api_conn(user)

    create_conn =
      post(api_conn, ~p"/api/notes", %{
        "content" => "# API note\n\nThe API body.",
        "visibility" => "authenticated"
      })

    assert %{"note" => %{"id" => note_id, "title" => "API note", "content" => content}} =
             json_response(create_conn, 201)

    assert content == "# API note\n\nThe API body."

    search_conn = get(api_conn, ~p"/api/notes/search?query=API+body")
    assert %{"results" => [%{"note" => %{"id" => ^note_id}}]} = json_response(search_conn, 200)

    update_conn =
      patch(api_conn, ~p"/api/notes/#{note_id}", %{"content" => "# Updated API note\n\nUpdated."})

    assert %{"note" => %{"title" => "Updated API note"}} = json_response(update_conn, 200)
    assert Notes.get_note(note_id).title == "Updated API note"
  end

  test "requires authentication", %{conn: conn} do
    assert %{"error" => "invalid_token"} =
             conn |> post(~p"/api/notes", %{"content" => "# Private"}) |> json_response(401)
  end

  defp api_conn(user) do
    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"scopes" => ["mcp"]}, token_type: "access_token")

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
  end
end
