defmodule Tuist.Push.LiveActivitiesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.LiveActivities
  alias Tuist.Push.LiveActivity
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user, session: session(user)}
  end

  test "replaces a sign-in's previous activity and keeps retirement monotonic", ctx do
    id = Ecto.UUID.generate()
    assert {:ok, _} = LiveActivities.register(ctx.user, ctx.session, id, params())
    assert {:ok, _} = LiveActivities.register(ctx.user, ctx.session, Ecto.UUID.generate(), params())
    assert Repo.get!(LiveActivity, id).retired_reason == "replaced"
    assert {:error, :retired} = LiveActivities.register(ctx.user, ctx.session, id, params())
    late = Ecto.UUID.generate()
    assert :ok = LiveActivities.unregister(ctx.user, late)
    assert {:error, :retired} = LiveActivities.register(ctx.user, ctx.session, late, params())
  end

  test "the same user's other sign-in cannot take an activity ID", ctx do
    id = Ecto.UUID.generate()
    assert {:ok, _} = LiveActivities.register(ctx.user, ctx.session, id, params())
    assert {:error, :conflict} = LiveActivities.register(ctx.user, session(ctx.user), id, params())
    other = AccountsFixtures.user_fixture()
    assert {:error, :conflict} = LiveActivities.register(other, session(other), id, params())
  end

  test "token supersession retires the old registration", ctx do
    params = params()
    first = Ecto.UUID.generate()
    assert {:ok, _} = LiveActivities.register(ctx.user, ctx.session, first, params)
    other = AccountsFixtures.user_fixture()
    assert {:ok, _} = LiveActivities.register(other, session(other), Ecto.UUID.generate(), params)
    assert Repo.get!(LiveActivity, first).retired_reason == "superseded"
  end

  test "expired grants cannot register", ctx do
    Token
    |> Repo.get!(ctx.session.oauth_grant_id)
    |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now())
    |> Repo.update!()

    assert {:error, :invalid} = LiveActivities.register(ctx.user, ctx.session, Ecto.UUID.generate(), params())
  end

  test "legacy jobs have no conversation queries or new work" do
    assert :done = LiveActivities.deliver(Ecto.UUID.generate())
    assert :ok = LiveActivities.start(Ecto.UUID.generate())
    assert :ok = LiveActivities.thread_changed(123)
  end

  test "only the registered owner's exact grant can dispatch an ActivityKit token", ctx do
    params = params()
    assert {:ok, _} = LiveActivities.register(ctx.user, ctx.session, Ecto.UUID.generate(), params)

    input =
      Map.merge(params, %{
        "payload" => %{"aps" => %{"event" => "update", "timestamp" => 1}},
        "options" => %{"priority" => 10, "expiration" => 123}
      })

    assert {:error, :invalid_token} = LiveActivities.dispatch(ctx.user, session(ctx.user), input)
    other = AccountsFixtures.user_fixture()
    assert {:error, :invalid_token} = LiveActivities.dispatch(other, session(other), input)

    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = JOSE.JWK.to_pem(jwk)
    stub(Environment, :apns_key_id, fn -> "K#{System.unique_integer([:positive])}" end)
    stub(Environment, :apns_team_id, fn -> "TEAM123456" end)
    stub(Environment, :apns_private_key, fn -> pem end)

    expect(Req, :post, fn _, options ->
      assert options[:json] == input["payload"]
      assert {"apns-topic", "dev.tuist.code.push-type.liveactivity"} in options[:headers]
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    assert :ok = LiveActivities.dispatch(ctx.user, ctx.session, input)
    :ok = LiveActivities.unregister(ctx.user, Repo.one!(LiveActivity).id)
    assert {:error, :invalid_token} = LiveActivities.dispatch(ctx.user, ctx.session, input)
  end

  defp params, do: %{"token" => Base.encode16(:crypto.strong_rand_bytes(32)), "environment" => "sandbox"}

  defp session(user) do
    client_id = Clients.luft_client_id()
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client_id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client_id,
      sub: to_string(user.id),
      scope: ""
    })

    {:ok, session} = Push.oauth_session(bearer, user, ["luft"])
    session
  end
end
