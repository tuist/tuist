defmodule TuistWeb.API.LuftNotificationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, client} = Clients.create_client(%{redirect_uris: ["https://luft.invalid/callback"], name: "notifications"})
    stub(Clients, :luft_server_client_id, fn -> client.id end)
    %{user: user, client: client}
  end

  test "the routed capability requires a live scoped Luft grant", %{user: user, client: client} do
    assert request(nil, alert()).status == 401
    assert request(oauth(user, client, ""), alert()).status == 403
    bearer = oauth(user, client, "luft:app")
    conn = request(bearer, alert())
    assert conn.status == 204
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    Token |> Repo.get_by!(value: bearer) |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
    assert request(bearer, alert()).status == 403
  end

  test "invalid kinds and external notification paths are rejected", %{user: user, client: client} do
    bearer = oauth(user, client, "luft:app")
    assert request(bearer, %{"kind" => "unknown"}).status == 400
    payload = put_in(alert(), ["payload", "url"], "https://foreign.invalid/private")
    assert request(bearer, payload).status == 400
  end

  defp request(bearer, body) do
    conn = put_req_header(build_conn(), "content-type", "application/json")
    conn = if bearer, do: put_req_header(conn, "authorization", "Bearer " <> bearer), else: conn
    post(conn, "/api/me/luft-notifications", JSON.encode!(body))
  end

  defp oauth(user, client, scope) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: scope
    })

    bearer
  end

  defp alert do
    %{
      "kind" => "alert",
      "notification_id" => Ecto.UUID.generate(),
      "payload" => %{"aps" => %{"alert" => %{"title" => "Luft", "body" => "Ready"}}, "url" => "/threads"}
    }
  end
end
