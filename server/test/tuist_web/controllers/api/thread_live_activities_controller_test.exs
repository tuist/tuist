defmodule TuistWeb.API.ThreadLiveActivitiesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push.LiveActivity
  alias Tuist.Push.LiveActivityStarter
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    %{user: AccountsFixtures.user_fixture(preload: [:account])}
  end

  test "only Luft registers, and a retired ID answers 410", %{conn: conn, user: user} do
    id = Ecto.UUID.generate()
    body = %{token: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower), environment: "production"}

    tuist_app = sign_in(user, Clients.public!().id)
    assert conn |> authorized(tuist_app) |> put("/api/me/thread-live-activities/#{id}", body) |> json_response(403)

    luft = sign_in(user, Clients.luft_client_id())
    assert build_conn() |> authorized(luft) |> put("/api/me/thread-live-activities/#{id}", body) |> response(204)
    assert %LiveActivity{user_id: user_id, retired_at: nil} = Repo.get!(LiveActivity, id)
    assert user_id == user.id

    assert build_conn() |> authorized(luft) |> delete("/api/me/thread-live-activities/#{id}") |> response(204)
    assert build_conn() |> authorized(luft) |> put("/api/me/thread-live-activities/#{id}", body) |> json_response(410)

    assert build_conn()
           |> authorized(luft)
           |> put("/api/me/thread-live-activities/#{Ecto.UUID.generate()}", %{body | token: "nope"})
           |> json_response(400)
  end

  test "only Luft registers a push-to-start token, and the sign-in forgets it", %{conn: conn, user: user} do
    body = %{
      token: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
      environment: "production",
      profile_id: "profile_1"
    }

    tuist_app = sign_in(user, Clients.public!().id)
    assert conn |> authorized(tuist_app) |> put("/api/me/thread-live-activity-starter", body) |> json_response(403)
    assert [] = Repo.all(LiveActivityStarter)

    luft = sign_in(user, Clients.luft_client_id())
    assert build_conn() |> authorized(luft) |> put("/api/me/thread-live-activity-starter", body) |> response(204)
    assert [%LiveActivityStarter{profile_id: "profile_1", environment: "production"}] = Repo.all(LiveActivityStarter)

    assert build_conn()
           |> authorized(luft)
           |> put("/api/me/thread-live-activity-starter", %{body | profile_id: "../profile"})
           |> json_response(400)

    assert build_conn() |> authorized(luft) |> delete("/api/me/thread-live-activity-starter") |> response(204)
    assert [] = Repo.all(LiveActivityStarter)
  end

  defp sign_in(user, client_id) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client_id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client_id,
      sub: to_string(user.id),
      scope: ""
    })

    bearer
  end

  defp authorized(conn, bearer) do
    conn
    |> put_req_header("authorization", "Bearer #{bearer}")
    |> put_req_header("content-type", "application/json")
  end
end
