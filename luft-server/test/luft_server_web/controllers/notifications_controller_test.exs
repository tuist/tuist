defmodule LuftServerWeb.NotificationsControllerTest do
  use LuftServerWeb.ConnCase, async: true

  alias LuftServer.Notifications.LiveActivity
  alias LuftServer.Notifications.LiveActivityStarter
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServerWeb.NotificationsController

  setup do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{
          "access_token" => "exact-upstream",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert ["Bearer exact-upstream"] = get_req_header(conn, "authorization")
      assert String.starts_with?(conn.request_path, "/api/me/thread-live-activit")
      send(self(), {:upstream, conn.method, conn.request_path})
      send_resp(conn, 204, "")
    end)

    %{
      session: session,
      params: %{
        "id" => Ecto.UUID.generate(),
        "token" => Base.encode16(:crypto.strong_rand_bytes(32)),
        "environment" => "sandbox"
      }
    }
  end

  test "public registration action binds exact local session and upstream lineage", ctx do
    assert %{status: 204} = NotificationsController.update(conn(ctx.session), ctx.params)
    row = Repo.get!(LiveActivity, ctx.params["id"])
    assert row.user_id == 1
    assert row.oauth_grant_id == ctx.session.id
    assert row.token == String.downcase(ctx.params["token"])
    assert_receive {:upstream, "PUT", path}
    assert path == "/api/me/thread-live-activities/#{row.id}"
    assert %{status: 204} = NotificationsController.delete(conn(ctx.session), ctx.params)
    assert Repo.reload!(row).token == nil
    assert %{status: 410} = NotificationsController.update(conn(ctx.session), ctx.params)
  end

  test "another sign-in for the same owner cannot rebind an activity", ctx do
    NotificationsController.update(conn(ctx.session), ctx.params)

    {:ok, _, other} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{
          "access_token" => "exact-upstream",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    assert %{status: 409} = NotificationsController.update(conn(other), ctx.params)
    assert Repo.get!(LiveActivity, ctx.params["id"]).oauth_grant_id == ctx.session.id
  end

  test "deletion tombstones survive transient upstream failure", ctx do
    Req.Test.stub(LuftServer.Tuist, &send_resp(&1, 503, ""))
    assert %{status: 502} = NotificationsController.delete(conn(ctx.session), ctx.params)
    assert Repo.get!(LiveActivity, ctx.params["id"]).retired_reason == "unregistered"
  end

  test "upstream rejection does not create a local registration", ctx do
    Req.Test.stub(LuftServer.Tuist, &send_resp(&1, 410, ""))
    assert %{status: 410} = NotificationsController.update(conn(ctx.session), ctx.params)
    assert Repo.get(LiveActivity, ctx.params["id"]) == nil
  end

  test "expired sessions cannot register even with a held session struct", ctx do
    Repo.delete!(ctx.session)
    assert %{status: 401} = NotificationsController.update(conn(ctx.session), ctx.params)
    refute_receive {:upstream, _, _}
    assert Repo.get(LiveActivity, ctx.params["id"]) == nil
  end

  test "push-to-start registration and retirement use the same session", ctx do
    params = Map.put(ctx.params, "profile_id", "profile_1")
    assert %{status: 204} = NotificationsController.update_starter(conn(ctx.session), params)
    assert Repo.one!(LiveActivityStarter).oauth_grant_id == ctx.session.id
    assert %{status: 204} = NotificationsController.delete_starter(conn(ctx.session), %{})
    assert Repo.all(LiveActivityStarter) == []
  end

  defp conn(session), do: assign(build_conn(), :session, session)
end
