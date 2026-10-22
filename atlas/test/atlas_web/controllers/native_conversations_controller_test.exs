defmodule AtlasWeb.NativeConversationsControllerTest do
  # Profiles bound to the conversations role are a singleton across the table.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use AtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.ConversationsFixtures

  alias Atlas.Conversations

  test "every route requires a bearer token, even with a browser session", %{conn: conn} do
    {session, _user} = log_in_user(conn)
    id = Ecto.UUID.generate()

    for api <- [conn, session],
        {method, path} <- [
          {:get, "/api/native/conversations"},
          {:post, "/api/native/conversations"},
          {:post, "/api/native/conversations/private"},
          {:get, "/api/native/conversations/#{id}/messages"},
          {:post, "/api/native/conversations/#{id}/messages"}
        ] do
      response = dispatch(api, @endpoint, method, path, %{})
      assert json_response(response, 401)["error"] == "invalid_token"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "lists the bot and the caller's conversations, private thread first" do
    user = user_fixture()
    api = bearer(user)

    assert %{"bot" => %{"name" => "Atlas", "configured" => false}, "conversations" => %{"items" => [], "page" => 1}} =
             api |> get("/api/native/conversations?page=1") |> json_response(200)

    conversations_profile_fixture()
    {:ok, _shared} = Conversations.create_shared(user, %{"title" => "Team"})
    private = api |> post("/api/native/conversations/private", %{}) |> json_response(201)
    assert api |> post("/api/native/conversations/private", %{}) |> json_response(200) == private

    body = api |> get("/api/native/conversations") |> json_response(200)
    assert body["bot"] == %{"name" => "Atlas", "configured" => true}
    assert %{"page" => 1, "total_pages" => 1, "total_count" => 2, "items" => [first, second]} = body["conversations"]
    assert first["id"] == private["conversation"]["id"]
    assert first["kind"] == "private" and first["title"] == "Atlas"
    assert second["kind"] == "shared" and second["title"] == "Team"

    assert Map.keys(first) |> Enum.sort() ==
             ~w(agent_status id kind latest_seq origin owner_id participants status summary title updated_at)

    assert first["participants"] == [%{"id" => user.id, "name" => user.name}]
    assert first["status"] == "active" and first["origin"] == "manual" and first["summary"] == ""

    assert api |> get("/api/native/conversations?page=0") |> json_response(422) == %{"error" => "invalid_params"}
  end

  test "creates shared conversations and validates participants" do
    user = user_fixture()
    teammate = user_fixture()
    api = bearer(user)

    created =
      api
      |> post("/api/native/conversations", %{title: "Launch", participant_ids: [teammate.id]})
      |> json_response(201)

    assert created["conversation"]["owner_id"] == user.id
    assert length(created["conversation"]["participants"]) == 2

    assert %{"error" => "validation_failed", "fields" => %{"participant_ids" => ["invalid"]}} =
             api
             |> post("/api/native/conversations", %{title: "x", participant_ids: ["https://evil.example"]})
             |> json_response(422)

    assert %{"error" => "validation_failed"} =
             api |> post("/api/native/conversations", %{title: " "}) |> json_response(422)
  end

  test "posts idempotently and returns history newest page first in chronological order" do
    conversations_profile_fixture()
    user = user_fixture()
    api = bearer(user)
    %{"conversation" => %{"id" => id}} = api |> post("/api/native/conversations/private", %{}) |> json_response(201)
    client_id = Ecto.UUID.generate()

    created =
      api
      |> post("/api/native/conversations/#{id}/messages", %{body: "Hello", client_id: client_id})
      |> json_response(201)

    assert %{
             "message" => %{
               "kind" => "human",
               "body" => "Hello",
               "author_id" => author_id,
               "author_name" => author_name,
               "tool_name" => nil,
               "tool_status" => nil,
               "tool_input" => "",
               "tool_output" => "",
               "seq" => 1
             }
           } = created

    assert author_id == user.id and author_name == user.name

    assert api
           |> post("/api/native/conversations/#{id}/messages", %{body: "Hello", client_id: client_id})
           |> json_response(200) ==
             created

    history = api |> get("/api/native/conversations/#{id}/messages?page=1") |> json_response(200)
    assert history["conversation"]["id"] == id
    assert history["conversation"]["agent_status"] == "queued"
    assert history["latest_seq"] == 1

    assert %{"items" => [%{"body" => "Hello"}], "page" => 1, "total_pages" => 1, "total_count" => 1} =
             history["messages"]

    assert %{"fields" => %{"client_id" => ["invalid"]}} =
             api
             |> post("/api/native/conversations/#{id}/messages", %{body: "Hi", client_id: "bad"})
             |> json_response(422)
  end

  test "non-participants get 404, indistinguishable from missing conversations" do
    owner = user_fixture()
    {:ok, conversation, _} = Conversations.ensure_private(owner)
    api = bearer(user_fixture(Atlas.Authorization.executive_scopes()))

    for path <- [
          "/api/native/conversations/#{conversation.id}/messages",
          "/api/native/conversations/#{Ecto.UUID.generate()}/messages"
        ] do
      assert api |> get(path) |> json_response(404) == %{"error" => "not_found"}

      assert api |> post(path, %{body: "x", client_id: Ecto.UUID.generate()}) |> json_response(404) == %{
               "error" => "not_found"
             }
    end
  end

  test "participants can be added by the owner and leave on their own" do
    owner = user_fixture()
    member = user_fixture()
    {:ok, conversation} = Conversations.create_shared(owner, %{"title" => "Team"})

    assert %{"participant" => %{"id" => id}} =
             owner
             |> bearer()
             |> post("/api/native/conversations/#{conversation.id}/participants", %{user_id: member.id})
             |> json_response(201)

    assert id == member.id

    assert member
           |> bearer()
           |> delete("/api/native/conversations/#{conversation.id}/participants/#{member.id}")
           |> json_response(200) == %{"removed" => true}
  end
end
