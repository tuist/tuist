defmodule AtlasWeb.OrbitLiveActivityControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.OrbitFixtures, only: [user_fixture: 0]
  import Atlas.PushFixtures
  import Ecto.Query

  alias Atlas.Orbit
  alias Atlas.Orbit.Run
  alias Atlas.Push.Config
  alias Atlas.Push.LiveActivity
  alias Atlas.Repo
  alias Boruta.Ecto.Token

  @path "/api/me/orbit-live-activity"

  setup do
    stub(Config, :available?, fn "ios" -> true end)
    stub(Config, :available?, fn "ios", _environment -> true end)
    user = user_fixture()
    {client_id, token} = native_access_token(user)
    api = put_req_header(build_conn(), "authorization", "Bearer #{token}")
    %{api: api, user: user, client_id: client_id, id: Ecto.UUID.generate()}
  end

  test "all routes are bearer-only, native-client-only and no-store", %{conn: conn, user: user, id: id} do
    {browser, _} = log_in_user(conn)
    {_client, token} = native_access_token(user, ["https://example.com/callback"])
    non_native = put_req_header(build_conn(), "authorization", "Bearer #{token}")

    for {method, path} <- [{:get, @path}, {:put, @path <> "/" <> id}, {:delete, @path <> "/" <> id}] do
      response = dispatch(browser, @endpoint, method, path, %{})
      assert json_response(response, 401)
      assert get_resp_header(response, "cache-control") == ["no-store"]
      response = dispatch(non_native, @endpoint, method, path, %{})
      assert json_response(response, 403) == %{"error" => "native_client_required"}
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "projection counts all concurrent eligible own runs, caps at three and orders by real time", %{
    api: api,
    user: user
  } do
    runs =
      for {offset, title} <- [
            {40, "  Cash\t\nflow\u00A0\u200B\u202E\u0001 forecast  "},
            {10, "Later conversation"},
            {30, String.duplicate("e\u0301", 81)},
            {20, " \t\u200B\u202E\u0001\u00A0 "}
          ],
          do: run(user, -offset, title)

    other = user_fixture()
    {:ok, shared} = Orbit.create_shared(other, %{"title" => "Secret title", "participant_ids" => [user.id]})
    Repo.insert!(%Run{thread_id: shared.id, acting_user_id: other.id, status: "running", trigger_seq: 0})

    hidden = run(user, -100, "Secret scope title")
    hidden.thread |> Ecto.Changeset.change(required_scopes: ["finance:read"]) |> Repo.update!()
    archived = run(user, -100, "Secret archived title")
    archived.thread |> Ecto.Changeset.change(status: "archived") |> Repo.update!()
    cancelled = run(user, -100, "Secret cancelled title")
    cancelled |> Ecto.Changeset.change(cancel_requested_at: DateTime.utc_now()) |> Repo.update!()
    removed = run(user, -100, "Secret membership title")
    Repo.delete_all(from p in Orbit.Participant, where: p.thread_id == ^removed.thread_id and p.user_id == ^user.id)

    Repo.transaction(fn ->
      Orbit.append!(hd(runs).thread, %{kind: "human", author_id: user.id, body: "Excluded raw prompt"})
      Orbit.append!(hd(runs).thread, %{kind: "agent", body: "Excluded raw reply"})
    end)

    response = get(api, @path)
    assert %{"available" => true, "content" => content} = json_response(response, 200)
    assert content["active_count"] == 4
    assert is_integer(content["updated_at"])
    expected = runs |> Enum.sort_by(&DateTime.to_unix(&1.inserted_at)) |> Enum.take(3)
    assert Enum.map(content["conversations"], & &1["id"]) == Enum.map(expected, & &1.thread_id)

    titles = ["Cash flow forecast", String.duplicate("e\u0301", 40), "Conversation"]

    for {{item, run}, title} <- Enum.zip(Enum.zip(content["conversations"], expected), titles) do
      assert item == %{
               "id" => run.thread_id,
               "title" => title,
               "status" => "queued",
               "started_at" => DateTime.to_unix(run.inserted_at),
               "completed_steps" => 0
             }

      assert item["title"] |> String.to_charlist() |> length() <= 80
    end

    refute response.resp_body =~ "Secret"
    refute response.resp_body =~ "Excluded raw"
    refute response.resp_body =~ user.name
    refute response.resp_body =~ "tool_name"
  end

  test "tokens are encrypted and redacted; refresh does not extend the ActivityKit lifetime", %{
    api: api,
    id: id,
    user: user,
    client_id: client_id
  } do
    body = body()
    assert api |> put(@path <> "/" <> id, body) |> json_response(200) == %{"registered" => true}
    row = Repo.get!(LiveActivity, id)
    assert row.user_id == user.id
    assert row.oauth_client_id == client_id
    assert DateTime.diff(row.expires_at, row.inserted_at) == 28_800
    refute inspect(row) =~ body["token"]
    {:ok, raw_id} = Ecto.UUID.dump(id)
    %{rows: [[encrypted]]} = Repo.query!("SELECT token FROM orbit_live_activities WHERE id = $1", [raw_id])
    refute encrypted == body["token"]
    assert api |> put(@path <> "/" <> id, body()) |> json_response(200) == %{"registered" => true}
    assert Repo.reload!(row).expires_at == row.expires_at
  end

  test "DELETE tombstones unknown and existing IDs, so a delayed PUT cannot resurrect them", %{api: api, id: id} do
    for register_first? <- [false, true] do
      id = if register_first?, do: Ecto.UUID.generate(), else: id
      if register_first?, do: assert(api |> put(@path <> "/" <> id, body()) |> json_response(200))
      assert api |> delete(@path <> "/" <> id) |> json_response(200) == %{"deleted" => true}
      assert api |> delete(@path <> "/" <> id) |> json_response(200) == %{"deleted" => true}
      assert api |> put(@path <> "/" <> id, body()) |> json_response(409) == %{"error" => "registration_retired"}
    end
  end

  test "owner AND native OAuth client are bound; neither may transfer or delete another binding", %{
    api: api,
    user: user,
    id: id
  } do
    assert api |> put(@path <> "/" <> id, body()) |> json_response(200)

    for owner <- [user, user_fixture()] do
      {_client, token} = native_access_token(owner)
      other = put_req_header(build_conn(), "authorization", "Bearer #{token}")
      assert other |> put(@path <> "/" <> id, body()) |> json_response(409) == %{"error" => "registration_conflict"}
      assert other |> delete(@path <> "/" <> id) |> json_response(200) == %{"deleted" => true}
      assert is_nil(Repo.get!(LiveActivity, id).retired_at)
    end
  end

  test "invalid IDs, odd/short/oversized/nonhex tokens and extra fields are rejected without echoing", %{
    api: api,
    id: id
  } do
    for token <- ["abc", String.duplicate("a", 31), String.duplicate("a", 513), String.duplicate("x", 64), 1, nil] do
      assert api |> put(@path <> "/" <> id, %{body() | "token" => token}) |> json_response(400) == %{
               "error" => "invalid_live_activity"
             }
    end

    for params <- [%{}, Map.put(body(), "owner_id", id), %{body() | "environment" => "other"}] do
      assert api |> put(@path <> "/" <> id, params) |> json_response(400)
    end

    for bad_id <- ["not-uuid", String.upcase(id)] do
      assert api |> put(@path <> "/" <> bad_id, body()) |> json_response(400)
      assert api |> delete(@path <> "/" <> bad_id) |> json_response(400)
    end
  end

  test "unsupported instances are harmless and cannot register", %{api: api, id: id} do
    stub(Config, :available?, fn "ios" -> false end)
    stub(Config, :available?, fn "ios", _ -> false end)

    assert %{"available" => false, "content" => %{"active_count" => 0, "conversations" => []}} =
             api |> get(@path) |> json_response(200)

    assert api |> put(@path <> "/" <> id, body()) |> json_response(503) == %{"error" => "live_activity_unavailable"}
    assert api |> delete(@path <> "/" <> id) |> json_response(200) == %{"deleted" => true}
  end

  test "a valid access token without a current refresh grant cannot register", %{api: api, client_id: client_id, id: id} do
    Repo.update_all(from(t in Token, where: t.client_id == ^client_id),
      set: [refresh_token_revoked_at: NaiveDateTime.utc_now()]
    )

    assert api |> put(@path <> "/" <> id, body()) |> json_response(401) == %{"error" => "session_ended"}
  end

  defp body, do: %{"token" => ios_token(), "environment" => "production"}

  defp run(user, seconds, title) do
    {:ok, thread, :created} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
    thread = thread |> Ecto.Changeset.change(title: title) |> Repo.update!()

    Repo.insert!(%Run{
      thread_id: thread.id,
      acting_user_id: user.id,
      status: "queued",
      trigger_seq: 0,
      inserted_at: DateTime.add(DateTime.utc_now(), seconds)
    })
    |> Map.put(:thread, thread)
  end
end
