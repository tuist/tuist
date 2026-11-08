defmodule AtlasWeb.NativeMoodboardControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.LLMs.Runner
  alias Atlas.Moodboard
  alias Atlas.Moodboard.Preview

  setup %{conn: conn} do
    {_conn, user} = log_in_user(conn)
    api = build_conn() |> put_req_header("authorization", "Bearer #{oauth_access_token_fixture(user)}")
    %{api: api, user: user}
  end

  test "sharing requires a bearer token rather than a browser session", %{conn: conn} do
    {browser, _} = log_in_user(conn)

    for request <- [conn, browser],
        {method, path} <- [
          {:post, "/api/native/moodboard/suggestions"},
          {:put, "/api/native/moodboard/captures/#{Ecto.UUID.generate()}"}
        ] do
      response = dispatch(request, @endpoint, method, path, %{})
      assert json_response(response, 401)["error"] == "invalid_token"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "review suggestions do not publish, and confirmed fields save with replay identity", %{api: api, user: user} do
    stub(Runner, :fetch_config, fn -> {:error, :llm_not_configured} end)
    stub(Preview, :fetch, fn _ -> {:ok, %{source_title: "Public page", source_description: "Page context"}} end)
    source = %{"url" => "https://example.com/#{System.unique_integer([:positive])}", "content" => ""}
    response = post(api, "/api/native/moodboard/suggestions", source)

    assert %{"suggestions" => %{"title" => "Public page", "description" => "Page context", "generated" => false}} =
             json_response(response, 200)

    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert {[], false} = Moodboard.list_resources(user)

    path = "/api/native/moodboard/captures/#{Ecto.UUID.generate()}"
    fields = Map.merge(source, %{"title" => "My reviewed title", "description" => "My note", "tags" => ["Type"]})
    saved = api |> put(path, fields) |> json_response(200)
    assert saved["saved"]
    assert api |> put(path, fields) |> json_response(200) == saved

    assert %{title: "My reviewed title", description: "My note", tags: ["type"], created_by_id: owner} =
             Moodboard.get_resource(user, saved["resource_id"])

    assert owner == user.id

    assert api |> put(path, Map.put(fields, "created_by_id", Ecto.UUID.generate())) |> json_response(422) == %{
             "error" => "invalid_capture"
           }

    assert api |> put(path, Map.put(fields, "title", "Changed")) |> json_response(409) == %{
             "error" => "capture_conflict"
           }
  end
end
