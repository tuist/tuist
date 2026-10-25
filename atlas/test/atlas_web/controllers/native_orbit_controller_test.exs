defmodule AtlasWeb.NativeOrbitControllerTest do
  # Profiles bound to the threads role are a singleton across the table.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use AtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.OrbitFixtures

  alias Atlas.Orbit
  alias Atlas.Orbit.Attachments
  alias Atlas.Orbit.Run
  alias Atlas.Repo

  test "every route requires a bearer token, even with a browser session", %{conn: conn} do
    {session, _user} = log_in_user(conn)
    id = Ecto.UUID.generate()

    for api <- [conn, session],
        {method, path} <- [
          {:get, "/api/native/orbit/threads"},
          {:post, "/api/native/orbit/threads"},
          {:post, "/api/native/orbit/threads/private"},
          {:get, "/api/native/orbit/threads/#{id}/people"},
          {:get, "/api/native/orbit/threads/#{id}/messages"},
          {:post, "/api/native/orbit/threads/#{id}/messages"},
          {:post, "/api/native/orbit/threads/#{id}/attachments"},
          {:get, "/api/native/orbit/threads/#{id}/attachments/#{id}"},
          {:delete, "/api/native/orbit/threads/#{id}/attachments/#{id}"}
        ] do
      response = dispatch(api, @endpoint, method, path, %{})
      assert json_response(response, 401)["error"] == "invalid_token"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "lists the bot and the caller's threads, private thread first" do
    user = user_fixture()
    api = bearer(user)

    assert %{
             "assistant" => %{"name" => "Pip", "configured" => false, "can_create_private" => true},
             "threads" => %{"items" => [], "page" => 1}
           } =
             api |> get("/api/native/orbit/threads?page=1") |> json_response(200)

    orbit_profile_fixture()
    {:ok, _shared} = Orbit.create_shared(user, %{"title" => "Team"})
    private = api |> post("/api/native/orbit/threads/private", %{}) |> json_response(201)
    assert api |> post("/api/native/orbit/threads/private", %{}) |> json_response(200) == private

    body = api |> get("/api/native/orbit/threads") |> json_response(200)
    assert body["assistant"] == %{"name" => "Pip", "configured" => true, "can_create_private" => true}
    assert %{"page" => 1, "total_pages" => 1, "total_count" => 2, "items" => [first, second]} = body["threads"]
    assert first["id"] == private["thread"]["id"]
    assert first["kind"] == "private" and first["title"] == "New conversation"
    assert second["kind"] == "shared" and second["title"] == "Team"

    assert Map.keys(first) |> Enum.sort() ==
             ~w(agent_status id kind latest_seq origin owner_id participants status summary title updated_at)

    assert first["participants"] == [%{"id" => user.id, "name" => user.name}]
    assert first["status"] == "active" and first["origin"] == "manual" and first["summary"] == ""

    assert api |> get("/api/native/orbit/threads?page=0") |> json_response(422) == %{"error" => "invalid_params"}
  end

  test "creates distinct private conversations, replays creation, and keeps histories owner-only" do
    user = user_fixture()
    other = user_fixture(Atlas.Authorization.executive_scopes())
    api = bearer(user)
    request_id = Ecto.UUID.generate()

    params = %{
      kind: "private",
      request_id: request_id,
      owner_id: other.id,
      participant_ids: [other.id],
      title: "Ignored"
    }

    first = api |> post("/api/native/orbit/threads", params) |> json_response(201)
    assert first == api |> post("/api/native/orbit/threads", params) |> json_response(200)

    second =
      api
      |> post("/api/native/orbit/threads", %{kind: "private", request_id: Ecto.UUID.generate()})
      |> json_response(201)

    assert first["thread"]["id"] != second["thread"]["id"]
    assert first["thread"]["title"] == "New conversation"
    assert first["thread"]["owner_id"] == user.id
    assert first["thread"]["participants"] == [%{"id" => user.id, "name" => user.name}]

    for {created, prompt} <- [{first, "First question"}, {second, "Different question"}] do
      id = created["thread"]["id"]
      message = %{body: prompt, client_id: Ecto.UUID.generate()}
      original = api |> post("/api/native/orbit/threads/#{id}/messages", message) |> json_response(201)
      assert original == api |> post("/api/native/orbit/threads/#{id}/messages", message) |> json_response(200)
      history = api |> get("/api/native/orbit/threads/#{id}/messages") |> json_response(200)
      assert history["thread"]["title"] == prompt
      assert history["messages"]["items"] |> Enum.filter(&(&1["kind"] == "human")) |> Enum.map(& &1["body"]) == [prompt]

      assert bearer(other) |> get("/api/native/orbit/threads/#{id}/messages") |> json_response(404) == %{
               "error" => "not_found"
             }
    end

    latest = api |> post("/api/native/orbit/threads/private", %{}) |> json_response(200)
    assert latest["thread"]["id"] == second["thread"]["id"]

    assert api |> post("/api/native/orbit/threads", %{kind: "private"}) |> json_response(422) ==
             %{"error" => "validation_failed", "fields" => %{"request_id" => ["invalid"]}}

    assert api |> post("/api/native/orbit/threads", %{kind: "other"}) |> json_response(422) == %{
             "error" => "invalid_params"
           }
  end

  test "private kind filtering applies before counts and pagination without hiding shared direct reads" do
    user = user_fixture()
    other = user_fixture()
    api = bearer(user)
    {:ok, shared} = Orbit.create_shared(user, %{"title" => "Direct-link shared"})
    {:ok, _, :created} = Orbit.create_private(other, %{"request_id" => Ecto.UUID.generate()})

    private_ids =
      for _ <- 1..26 do
        {:ok, thread, :created} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
        thread.id
      end

    first = api |> get("/api/native/orbit/threads?kind=private&page=1") |> json_response(200)
    second = api |> get("/api/native/orbit/threads?kind=private&page=2") |> json_response(200)
    assert first["threads"]["total_count"] == 26
    assert first["threads"]["total_pages"] == 2
    assert length(first["threads"]["items"]) == 25
    assert length(second["threads"]["items"]) == 1

    assert Enum.sort(Enum.map(first["threads"]["items"] ++ second["threads"]["items"], & &1["id"])) ==
             Enum.sort(private_ids)

    assert api
           |> get("/api/native/orbit/threads/#{shared.id}/messages")
           |> json_response(200)
           |> get_in(["thread", "id"]) == shared.id

    assert api |> get("/api/native/orbit/threads?kind=invalid") |> json_response(422) == %{"error" => "invalid_params"}

    assert api |> get("/api/native/orbit/threads?kind[]=private") |> json_response(422) == %{
             "error" => "invalid_params"
           }
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

  test "history exposes the durable research parent without flattening child evidence" do
    orbit_profile_fixture()
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    {:ok, _, :created} = Orbit.post_message(owner, thread, %{"body" => "Research", "client_id" => Ecto.UUID.generate()})
    run = Repo.get_by!(Run, thread_id: thread.id)

    {:ok, {parent, child}} =
      Repo.transaction(fn ->
        parent = Orbit.append!(thread, %{kind: "tool", run_id: run.id, tool_name: "task", tool_status: "succeeded"})

        child =
          Orbit.append!(thread, %{
            kind: "tool",
            run_id: run.id,
            parent_message_id: parent.id,
            tool_name: "list_accounts",
            tool_status: "succeeded",
            tool_output: "Child evidence"
          })

        {parent, child}
      end)

    response = owner |> bearer() |> get("/api/native/orbit/threads/#{thread.id}/messages") |> json_response(200)
    messages = response["messages"]["items"]
    assert Enum.find(messages, &(&1["id"] == parent.id))["parent_message_id"] == nil
    assert Enum.find(messages, &(&1["id"] == child.id))["parent_message_id"] == parent.id
    assert Enum.find(messages, &(&1["id"] == child.id))["tool_output"] == "Child evidence"
  end

  test "native attachments upload privately, post attachment-only, replay, and download under current access" do
    owner = user_fixture()
    member = user_fixture()
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Files", "participant_ids" => [member.id]})
    path = "/api/native/orbit/threads/#{thread.id}"
    params = attachment_params(png_fixture(), %{"filename" => "../../image.png", "content_type" => "image/png"})
    response = member |> bearer() |> post("#{path}/attachments", params)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert %{"attachment" => attachment} = json_response(response, 201)
    assert Map.keys(attachment) |> Enum.sort() == ~w(byte_size content_type filename id)
    assert attachment["filename"] == "image.png"

    assert member |> bearer() |> post("#{path}/attachments", params) |> json_response(201) == %{
             "attachment" => attachment
           }

    assert member
           |> bearer()
           |> post("#{path}/attachments", Map.put(params, "data", Base.encode64("changed")))
           |> json_response(422) == %{
             "error" => "validation_failed",
             "fields" => %{"client_id" => ["invalid"]}
           }

    attachment_path = "#{path}/attachments/#{attachment["id"]}"
    assert owner |> bearer() |> get(attachment_path) |> json_response(404) == %{"error" => "not_found"}
    assert owner |> bearer() |> delete(attachment_path) |> json_response(404) == %{"error" => "not_found"}

    send_params = %{client_id: Ecto.UUID.generate(), attachment_ids: [attachment["id"]], address_agent: false}
    created = member |> bearer() |> post("#{path}/messages", send_params) |> json_response(201)
    assert created["message"]["body"] == ""
    assert created["message"]["attachments"] == [attachment]
    assert member |> bearer() |> post("#{path}/messages", send_params) |> json_response(200) == created

    assert owner |> bearer() |> get("#{path}/messages") |> json_response(200) |> get_in(["messages", "items"]) == [
             created["message"]
           ]

    download = owner |> bearer() |> get(attachment_path)
    assert get_resp_header(download, "cache-control") == ["no-store"]
    assert json_response(download, 200) == %{"attachment" => Map.put(attachment, "data", params["data"])}
    assert member |> bearer() |> delete(attachment_path) |> json_response(404) == %{"error" => "not_found"}
    :ok = Orbit.remove_participant(owner, thread, member.id)
    assert member |> bearer() |> get(attachment_path) |> json_response(404) == %{"error" => "not_found"}
  end

  test "pending deletion is owner-only and attachment endpoints reject foreign threads, invalid fields and archives" do
    user = user_fixture()
    {:ok, thread} = Orbit.create_shared(user, %{"title" => "Files"})
    {:ok, other} = Orbit.create_shared(user, %{"title" => "Other"})
    path = "/api/native/orbit/threads/#{thread.id}/attachments"
    attachment = attachment_fixture(user, thread)
    cross = "/api/native/orbit/threads/#{other.id}/attachments/#{attachment.id}"
    assert user |> bearer() |> get(cross) |> json_response(404) == %{"error" => "not_found"}
    assert user |> bearer() |> delete(cross) |> json_response(404) == %{"error" => "not_found"}

    assert user |> bearer() |> post(path, attachment_params("x", %{"data" => "bad"})) |> json_response(422) == %{
             "error" => "validation_failed",
             "fields" => %{"attachment" => ["invalid"]}
           }

    assert user |> bearer() |> delete("#{path}/#{attachment.id}") |> json_response(200) == %{"deleted" => true}
    assert user |> bearer() |> get("#{path}/#{attachment.id}") |> json_response(404) == %{"error" => "not_found"}
    Repo.update!(Ecto.Changeset.change(thread, status: "archived"))
    assert user |> bearer() |> post(path, attachment_params()) |> json_response(409) == %{"error" => "archived"}

    assert user_fixture() |> bearer() |> post(path, attachment_params()) |> json_response(404) == %{
             "error" => "not_found"
           }
  end

  test "a full 5MiB upload fits the existing JSON parser; larger files are rejected" do
    user = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(user)
    path = "/api/native/orbit/threads/#{thread.id}/attachments"
    bytes = :binary.copy("x", Attachments.max_bytes())
    payload = JSON.encode!(attachment_params(bytes))
    assert byte_size(payload) < 8_000_000
    response = user |> bearer() |> put_req_header("content-type", "application/json") |> post(path, payload)
    assert json_response(response, 201)["attachment"]["byte_size"] == byte_size(bytes)
    oversized = JSON.encode!(attachment_params(bytes <> "x"))

    assert user
           |> bearer()
           |> put_req_header("content-type", "application/json")
           |> post(path, oversized)
           |> json_response(422)
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

  test "mention directory returns bounded name-only eligible choices and literal search" do
    owner = user_fixture(["finance:read", "documents:read"])
    allowed = user_fixture(["finance:write", "documents:read"], "Allowed%_")
    denied = user_fixture(["finance:read"], "Allowed%_")
    {:ok, thread, _} = Orbit.ensure_private(owner)
    thread = Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["finance:read", "documents:read"]))
    path = "/api/native/orbit/threads/#{thread.id}/people"
    response = owner |> bearer() |> get(path, %{query: "Allowed%_"})
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert json_response(response, 200) == %{"people" => [%{"id" => allowed.id, "name" => allowed.name}]}
    assert denied |> bearer() |> get(path) |> json_response(404) == %{"error" => "not_found"}

    for query <- [String.duplicate("x", 101), <<0>>, ["nested"], %{bad: "shape"}] do
      assert owner |> bearer() |> get(path, %{query: query}) |> json_response(422)
    end

    for _ <- 1..22, do: user_fixture(["finance:read", "documents:read"], "Choice")
    assert %{"people" => choices} = owner |> bearer() |> get(path, %{query: "Choice"}) |> json_response(200)
    assert length(choices) == 20
    assert Enum.all?(choices, &(Enum.sort(Map.keys(&1)) == ["id", "name"]))
  end

  test "message mentions promote private history without granting nonparticipant access" do
    owner = user_fixture()
    newcomer = user_fixture()
    stranger = user_fixture(Atlas.Authorization.executive_scopes())
    {:ok, thread, _} = Orbit.ensure_private(owner)
    path = "/api/native/orbit/threads/#{thread.id}"

    params = %{
      body: "Please join this conversation",
      client_id: Ecto.UUID.generate(),
      mention_ids: [newcomer.id],
      address_agent: false
    }

    assert %{"message" => message} = owner |> bearer() |> post(path <> "/messages", params) |> json_response(201)
    assert message["mentioned_user_ids"] == [newcomer.id]
    assert message["notice_kind"] == nil
    assert owner |> bearer() |> post(path <> "/messages", params) |> json_response(200) == %{"message" => message}

    assert %{"thread" => shared, "messages" => %{"items" => [_, notice]}} =
             newcomer |> bearer() |> get(path <> "/messages") |> json_response(200)

    assert shared["kind"] == "shared"
    assert shared["title"] == params.body
    assert notice["kind"] == "system" and notice["notice_kind"] == "handoff"
    assert notice["mentioned_user_ids"] == []
    assert notice["body"] =~ "Initial request (excerpt)"
    assert stranger |> bearer() |> get(path <> "/messages") |> json_response(404)

    assert %{"people" => [%{"id" => owner_id}]} = newcomer |> bearer() |> get(path <> "/people") |> json_response(200)
    assert owner_id == owner.id

    assert newcomer
           |> bearer()
           |> post(path <> "/messages", %{params | client_id: Ecto.UUID.generate(), mention_ids: [stranger.id]})
           |> json_response(403)
  end

  test "uncertain private creation replay after promotion conflicts safely instead of creating another conversation" do
    owner = user_fixture()
    newcomer = user_fixture()
    request_id = Ecto.UUID.generate()
    {:ok, thread, _} = Orbit.create_private(owner, %{"request_id" => request_id})

    assert owner
           |> bearer()
           |> post("/api/native/orbit/threads/#{thread.id}/messages", %{
             body: "Join",
             client_id: Ecto.UUID.generate(),
             mention_ids: [newcomer.id],
             address_agent: false
           })
           |> json_response(201)

    assert owner
           |> bearer()
           |> post("/api/native/orbit/threads", %{kind: "private", request_id: request_id})
           |> json_response(409) ==
             %{"error" => "thread_promoted"}

    assert {:ok, same} = Orbit.fetch(owner, thread.id)
    assert same.kind == "shared" and same.request_id == request_id
    assert {[_], %{total_count: 1}} = Orbit.list_for_user(owner)
    assert {:ok, own, :created} = Orbit.create_private(newcomer, %{"request_id" => request_id})
    assert own.id != thread.id

    assert %{rows: [[definition]]} =
             Repo.query!(
               "SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'orbit_threads_private_request_index'"
             )

    assert definition =~ "WHERE (request_id IS NOT NULL)"
    refute definition =~ "kind"
  end

  test "invalid mentions fail atomically and without revealing the target" do
    owner = user_fixture(["finance:read"])
    denied = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["finance:read"]))
    path = "/api/native/orbit/threads/#{thread.id}/messages"

    for ids <- [[denied.id], [Ecto.UUID.generate()], ["bad"], nil, %{}, List.duplicate(denied.id, 11)] do
      assert owner
             |> bearer()
             |> post(path, %{body: "Do not share", client_id: Ecto.UUID.generate(), mention_ids: ids})
             |> json_response(422) ==
               %{"error" => "validation_failed", "fields" => %{"mention_ids" => ["invalid"]}}

      assert Repo.reload!(thread).kind == "private" and Repo.reload!(thread).last_seq == 0
    end
  end
end
