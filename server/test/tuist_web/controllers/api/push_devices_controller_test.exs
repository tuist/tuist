defmodule TuistWeb.API.PushDevicesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Notifications
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)

    %{user: user, bearer: sign_in(user, Clients.public!())}
  end

  defp sign_in(user, client) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    bearer
  end

  defp device,
    do: %{platform: "ios", token: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower), environment: "sandbox"}

  defp authorized(conn, bearer) do
    conn
    |> put_req_header("authorization", "Bearer #{bearer}")
    |> put_req_header("content-type", "application/json")
  end

  test "registers and unregisters the signed-in app's installation", %{conn: conn, user: user, bearer: bearer} do
    id = Ecto.UUID.generate()

    conn = conn |> authorized(bearer) |> put("/api/me/push-devices/#{id}", device())

    assert %{"registration_id" => registration_id} = json_response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert [%{id: ^registration_id}] = Push.live_installations(user.id)

    conn = build_conn() |> authorized(bearer) |> delete("/api/me/push-devices/#{id}")
    assert response(conn, 204)
    assert Push.live_installations(user.id) == []

    conn = build_conn() |> authorized(bearer) |> put("/api/me/push-devices/#{id}", device())
    assert %{"reason" => "retired"} = json_response(conn, 410)
  end

  test "lists devices and reports devices removed from the device list", %{conn: conn, user: user, bearer: bearer} do
    id = Ecto.UUID.generate()
    device = Map.put(device(), :name, "iPhone 17 Pro")
    conn |> authorized(bearer) |> put("/api/me/push-devices/#{id}", device) |> json_response(200)

    assert %{"devices" => [%{"installation_id" => ^id, "name" => "iPhone 17 Pro", "platform" => "ios"} = listed]} =
             build_conn() |> authorized(bearer) |> get("/api/me/push-devices") |> json_response(200)

    assert build_conn()
           |> authorized(bearer)
           |> delete("/api/me/push-device-registrations/#{listed["registration_id"]}")
           |> response(204)

    assert Push.live_installations(user.id) == []

    assert %{"reason" => "removed"} =
             build_conn() |> authorized(bearer) |> put("/api/me/push-devices/#{id}", device) |> json_response(410)
  end

  test "reads and updates notification preferences per account and project", %{user: user, bearer: bearer} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, name: "ios-app")
    handle = user.account.name
    base = "/api/me/notification-preferences/new_preview"

    assert %{
             "kind" => "new_preview",
             "accounts" => [
               %{
                 "handle" => ^handle,
                 "enabled" => true,
                 "projects" => [%{"handle" => "ios-app", "setting" => "default", "enabled" => true}]
               }
             ]
           } = build_conn() |> authorized(bearer) |> get(base) |> json_response(200)

    assert %{"accounts" => [%{"enabled" => false, "projects" => [%{"setting" => "default", "enabled" => false}]}]} =
             build_conn()
             |> authorized(bearer)
             |> put("#{base}/accounts/#{handle}", %{enabled: false})
             |> json_response(200)

    assert %{"accounts" => [%{"enabled" => false, "projects" => [%{"setting" => "on", "enabled" => true}]}]} =
             build_conn()
             |> authorized(bearer)
             |> put("#{base}/projects/#{handle}/ios-app", %{setting: "on"})
             |> json_response(200)

    assert Notifications.notify?(user.id, "new_preview", project.id)

    foreign = ProjectsFixtures.project_fixture(preload: [:account])

    assert build_conn()
           |> authorized(bearer)
           |> put("#{base}/projects/#{foreign.account.name}/#{foreign.name}", %{setting: "off"})
           |> json_response(404)

    assert build_conn()
           |> authorized(bearer)
           |> put("#{base}/accounts/#{foreign.account.name}", %{enabled: false})
           |> json_response(404)

    assert build_conn() |> authorized(bearer) |> get("/api/me/notification-preferences/unknown") |> json_response(404)
  end

  test "ignores unknown device fields so newer apps can send them", %{conn: conn, user: user, bearer: bearer} do
    other_user = AccountsFixtures.user_fixture()

    conn =
      conn
      |> authorized(bearer)
      |> put("/api/me/push-devices/#{Ecto.UUID.generate()}", Map.put(device(), :user_id, other_user.id))

    assert %{"registration_id" => registration_id} = json_response(conn, 200)
    assert [%{id: ^registration_id}] = Push.live_installations(user.id)
    assert Push.live_installations(other_user.id) == []
  end

  test "tells throttled writes when to retry, without limiting reads", %{user: user, bearer: bearer} do
    key = "app_session:writes:user:#{user.id}"

    stub(TuistWeb.RateLimit, :hit, fn
      ^key, _opts -> {:deny, 12_001}
      other_key, opts -> Mimic.call_original(TuistWeb.RateLimit, :hit, [other_key, opts])
    end)

    conn = build_conn() |> authorized(bearer) |> put("/api/me/push-devices/#{Ecto.UUID.generate()}", device())

    assert json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") == ["13"]
    assert Push.live_installations(user.id) == []

    assert build_conn() |> authorized(bearer) |> get("/api/me/push-devices") |> json_response(200)
  end

  test "rejects credentials that are not a Tuist app sign-in", %{user: user} do
    {:ok, {_, account_token}} =
      Accounts.create_account_token(%{
        account: user.account,
        scopes: ["account:cache:read"],
        name: "push-test-token"
      })

    # A client registered through dynamic client registration, such as an MCP client the user authorized.
    {:ok, other_client} = Clients.create_client(%{redirect_uris: ["https://example.com/callback"], name: "other"})
    other_client_bearer = sign_in(user, other_client)

    for bearer <- [account_token, other_client_bearer] do
      for request <- [
            &put(&1, "/api/me/push-devices/#{Ecto.UUID.generate()}", device()),
            # Rejected before its body is validated.
            &put(&1, "/api/me/push-devices/#{Ecto.UUID.generate()}", %{unknown: true}),
            &get(&1, "/api/me/push-devices"),
            &get(&1, "/api/me/notification-preferences/new_preview"),
            &put(&1, "/api/me/notification-preferences/new_preview/accounts/#{user.account.name}", %{enabled: false})
          ] do
        assert build_conn() |> authorized(bearer) |> request.() |> json_response(403)
      end
    end

    assert Push.live_installations(user.id) == []
    assert [%{enabled: true}] = Notifications.preferences(user, "new_preview")
  end
end
