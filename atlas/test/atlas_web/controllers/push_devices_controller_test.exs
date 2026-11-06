defmodule AtlasWeb.PushDevicesControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.PushFixtures

  alias Atlas.Push.Config
  alias Atlas.Push.Installation
  alias Atlas.Repo

  setup %{conn: conn} do
    stub(Config, :available?, fn platform, _environment -> platform in ["ios", "android"] end)
    {_conn, user} = log_in_user(conn)
    {client_id, token} = native_access_token(user)
    api = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    %{api: api, user: user, client_id: client_id, installation_id: Ecto.UUID.generate()}
  end

  defp path(id), do: "/api/me/push-devices/#{id}"

  test "requires bearer authentication even with a browser session", %{conn: conn, installation_id: id} do
    {conn, _user} = log_in_user(conn)

    for method <- [:put, :delete] do
      assert conn |> dispatch(@endpoint, method, path(id), ios_device()) |> json_response(401)
    end
  end

  test "rejects tokens issued to non-native OAuth clients", %{user: user, installation_id: id} do
    for redirect_uris <- [
          ["https://example.com/callback"],
          ["dev.tuist.atlas://oauth-callback", "https://example.com/cb"]
        ] do
      {_client_id, token} = native_access_token(user, redirect_uris)
      api = build_conn() |> put_req_header("authorization", "Bearer #{token}")

      for method <- [:put, :delete] do
        assert api |> dispatch(@endpoint, method, path(id), ios_device()) |> json_response(403) == %{
                 "error" => "native_client_required"
               }
      end
    end

    assert Repo.aggregate(Installation, :count) == 0
  end

  test "registers, refreshes and deletes the caller's installation",
       %{api: api, user: user, installation_id: id} = ctx do
    response = put(api, path(id), ios_device(%{"environment" => "sandbox"}))
    assert %{"registered" => true, "registration_id" => registration_id} = json_response(response, 200)
    assert get_resp_header(response, "cache-control") == ["no-store"]

    installation = Repo.get!(Installation, registration_id)
    assert installation.user_id == user.id
    assert installation.oauth_client_id == ctx.client_id
    refute response.resp_body =~ installation.token

    assert %{"registration_id" => ^registration_id} = api |> put(path(id), ios_device()) |> json_response(200)
    assert api |> delete(path(id)) |> json_response(200) == %{"deleted" => true}
    assert api |> delete(path(id)) |> json_response(200) == %{"deleted" => true}
  end

  test "a stale registration after deletion is rejected so the client rotates", %{api: api, installation_id: id} do
    assert api |> delete(path(id)) |> json_response(200) == %{"deleted" => true}
    assert api |> put(path(id), android_device()) |> json_response(409) == %{"error" => "installation_retired"}
    assert %{"registered" => true} = api |> put(path(Ecto.UUID.generate()), android_device()) |> json_response(200)
  end

  test "another user's installation cannot be claimed or deleted", %{api: api, installation_id: id} do
    assert %{"registration_id" => registration_id} = api |> put(path(id), ios_device()) |> json_response(200)

    other = user_fixture_with_native_api()

    assert other |> put(path(id), ios_device()) |> json_response(409) == %{"error" => "installation_conflict"}
    assert other |> delete(path(id)) |> json_response(200) == %{"deleted" => true}
    assert Repo.get!(Installation, registration_id).retired_at == nil
  end

  test "rejects malformed bodies without echoing them", %{api: api, user: user, installation_id: id} do
    for body <- [
          %{},
          ios_device(%{"token" => "nothex"}),
          android_device(%{"environment" => "sandbox"}),
          Map.put(ios_device(), "user_id", user.id),
          Map.put(ios_device(), "app_id", "dev.tuist.atlas.settings-preview")
        ] do
      assert api |> put(path(id), body) |> json_response(400) == %{"error" => "invalid_push_device"}
    end

    assert api |> put(path("not-a-uuid"), ios_device()) |> json_response(400) == %{"error" => "invalid_push_device"}
    assert api |> delete(path("not-a-uuid")) |> json_response(400) == %{"error" => "invalid_push_device"}
  end

  test "reports unconfigured providers", %{api: api, installation_id: id} do
    stub(Config, :available?, fn _platform, _environment -> false end)
    assert api |> put(path(id), ios_device()) |> json_response(503) == %{"error" => "push_unavailable"}
  end

  test "profile advertises configured push platforms", %{api: api} do
    stub(Config, :capabilities, fn -> %{"ios" => true, "android" => false} end)

    assert %{"push_notifications" => %{"ios" => true, "android" => false}} =
             api |> get("/api/native/profile") |> json_response(200)
  end

  defp user_fixture_with_native_api do
    {_conn, user} = log_in_user(build_conn())
    {_client_id, token} = native_access_token(user)
    put_req_header(build_conn(), "authorization", "Bearer #{token}")
  end
end
