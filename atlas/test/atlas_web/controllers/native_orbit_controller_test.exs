defmodule AtlasWeb.NativeOrbitControllerTest do
  # Profiles bound to the threads role are a singleton across the table.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use AtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.OrbitFixtures

  alias Atlas.Orbit
  alias Atlas.Repo

  test "every route requires a bearer token, even with a browser session", %{conn: conn} do
    {session, _user} = log_in_user(conn)
    id = Ecto.UUID.generate()

    for api <- [conn, session],
        {method, path} <- [
          {:get, "/api/native/orbit/threads"},
          {:post, "/api/native/orbit/threads"},
          {:post, "/api/native/orbit/threads/private"},
          {:get, "/api/native/orbit/threads/#{id}/messages"},
          {:post, "/api/native/orbit/threads/#{id}/messages"}
        ] do
      response = dispatch(api, @endpoint, method, path, %{})
      assert json_response(response, 401)["error"] == "invalid_token"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "lists the bot and the caller's threads, private thread first" do
    user = user_fixture()
    api = bearer(user)

    assert %{"assistant" => %{"name" => "Atlas", "configured" => false}, "threads" => %{"items" => [], "page" => 1}} =
             api |> get("/api/native/orbit/threads?page=1") |> json_response(200)

    orbit_profile_fixture()
    {:ok, _shared} = Orbit.create_shared(user, %{"title" => "Team"})
    private = api |> post("/api/native/orbit/threads/private", %{}) |> json_response(201)
    assert api |> post("/api/native/orbit/threads/private", %{}) |> json_response(200) == private

    body = api |> get("/api/native/orbit/threads") |> json_response(200)
    assert body["assistant"] == %{"name" => "Atlas", "configured" => true}
    assert %{"page" => 1, "total_pages" => 1, "total_count" => 2, "items" => [first, second]} = body["threads"]
    assert first["id"] == private["thread"]["id"]
    assert first["kind"] == "private" and first["title"] == "Atlas"
    assert second["kind"] == "shared" and second["title"] == "Team"

    assert Map.keys(first) |> Enum.sort() ==
             ~w(agent_status id kind latest_seq origin owner_id participants status summary title updated_at)

    assert first["participants"] == [%{"id" => user.id, "name" => user.name}]
    assert first["status"] == "active" and first["origin"] == "manual" and first["summary"] == ""

    assert api |> get("/api/native/orbit/threads?page=0") |> json_response(422) == %{"error" => "invalid_params"}
  end

  test "creates shared threads and validates participants" do
    user = user_fixture()
    teammate = user_fixture()
    api = bearer(user)

    created =
      api
      |> post("/api/native/orbit/threads", %{title: "Launch", participant_ids: [teammate.id]})
      |> json_response(201)

    assert created["thread"]["owner_id"] == user.id
    assert length(created["thread"]["participants"]) == 2

    assert %{"error" => "validation_failed", "fields" => %{"participant_ids" => ["invalid"]}} =
             api
             |> post("/api/native/orbit/threads", %{title: "x", participant_ids: ["https://evil.example"]})
             |> json_response(422)

    assert %{"error" => "validation_failed"} =
             api |> post("/api/native/orbit/threads", %{title: " "}) |> json_response(422)
  end

  test "posts idempotently and returns history newest page first in chronological order" do
    orbit_profile_fixture()
    user = user_fixture()
    api = bearer(user)
    %{"thread" => %{"id" => id}} = api |> post("/api/native/orbit/threads/private", %{}) |> json_response(201)
    client_id = Ecto.UUID.generate()

    created =
      api
      |> post("/api/native/orbit/threads/#{id}/messages", %{body: "Hello", client_id: client_id})
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
           |> post("/api/native/orbit/threads/#{id}/messages", %{body: "Hello", client_id: client_id})
           |> json_response(200) ==
             created

    history = api |> get("/api/native/orbit/threads/#{id}/messages?page=1") |> json_response(200)
    assert history["thread"]["id"] == id
    assert history["thread"]["agent_status"] == "queued"
    assert history["latest_seq"] == 1

    assert %{"items" => [%{"body" => "Hello"}], "page" => 1, "total_pages" => 1, "total_count" => 1} =
             history["messages"]

    assert %{"fields" => %{"client_id" => ["invalid"]}} =
             api
             |> post("/api/native/orbit/threads/#{id}/messages", %{body: "Hi", client_id: "bad"})
             |> json_response(422)
  end

  test "non-participants get 404, indistinguishable from missing threads" do
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    api = bearer(user_fixture(Atlas.Authorization.executive_scopes()))

    for path <- [
          "/api/native/orbit/threads/#{thread.id}/messages",
          "/api/native/orbit/threads/#{Ecto.UUID.generate()}/messages"
        ] do
      assert api |> get(path) |> json_response(404) == %{"error" => "not_found"}

      assert api |> post(path, %{body: "x", client_id: Ecto.UUID.generate()}) |> json_response(404) == %{
               "error" => "not_found"
             }
    end
  end

  test "cards are server projections of authorized durable messages and disappear with access" do
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)

    {:ok, _} =
      Repo.transaction(fn ->
        Orbit.append!(thread, %{
          kind: "tool",
          tool_name: "list_accounts",
          tool_status: "succeeded",
          tool_output: JSON.encode!(%{"accounts" => [%{"name" => "Northstar"}]})
        })
      end)

    response = owner |> bearer() |> get("/api/native/orbit/threads/#{thread.id}/messages") |> json_response(200)
    [message] = response["messages"]["items"]
    assert message["component"]["type"] == "result_table"
    assert message["component"]["data"]["rows"] == [["Northstar"]]
    assert message["component"]["actions"] == [%{"id" => "show_evidence", "label" => "View source"}]

    thread |> Ecto.Changeset.change(required_scopes: ["accounts:read"]) |> Repo.update!()

    assert owner |> bearer() |> get("/api/native/orbit/threads/#{thread.id}/messages") |> json_response(404) == %{
             "error" => "not_found"
           }
  end

  test "participants can be added by the owner and leave on their own" do
    owner = user_fixture()
    member = user_fixture()
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Team"})

    assert %{"participant" => %{"id" => id}} =
             owner
             |> bearer()
             |> post("/api/native/orbit/threads/#{thread.id}/participants", %{user_id: member.id})
             |> json_response(201)

    assert id == member.id

    assert member
           |> bearer()
           |> delete("/api/native/orbit/threads/#{thread.id}/participants/#{member.id}")
           |> json_response(200) == %{"removed" => true}
  end
end
