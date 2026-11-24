defmodule Tuist.Push.Workers.ThreadFinishedWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Push.Workers.ThreadFinishedWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    client_id = Ecto.UUID.generate()
    stub(Environment, :luft_server_oauth_client_id, fn -> client_id end)
    stub(Environment, :luft_server_oauth_client_secret, fn -> "secret" end)
    stub(Environment, :luft_server_oauth_redirect_uris, fn -> ["https://luft.example/team/auth/callback"] end)
    stub(Environment, :oidc_signing_key, fn -> "unused" end)
    user = AccountsFixtures.user_fixture()
    {bearer, session} = session(user, client_id)
    device = register(user, session)
    %{user: user, bearer: bearer, session: session, client_id: client_id, device: device}
  end

  test "old source jobs cannot query source threads" do
    assert {:cancel, :moved_to_luft} =
             perform_job(ThreadFinishedWorker, %{"thread_id" => Ecto.UUID.generate(), "status" => "idle"})
  end

  test "generic dispatch targets only this authenticated user's exact grant and rewrites origin", ctx do
    {_bearer, other_session} = session(ctx.user, ctx.client_id)
    register(ctx.user, other_session)
    assert :ok = Push.dispatch_luft(ctx.user, ctx.bearer, input())
    assert [job] = all_enqueued(worker: DeliveryWorker)
    assert job.args["registration_id"] == ctx.device.id
    assert job.args["oauth_grant_id"] == ctx.session.oauth_grant_id
    assert job.args["payload"]["url"] == "https://luft.example/team/luft/threads/example"
    assert :ok = Push.dispatch_luft(ctx.user, ctx.bearer, input())
    assert [_] = all_enqueued(worker: DeliveryWorker)
  end

  test "cannot dispatch as another user or after grant revocation", ctx do
    other = AccountsFixtures.user_fixture()
    assert {:error, :forbidden} = Push.dispatch_luft(other, ctx.bearer, input())

    Token
    |> Repo.get!(ctx.session.oauth_grant_id)
    |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now())
    |> Repo.update!()

    assert {:error, :forbidden} = Push.dispatch_luft(ctx.user, ctx.bearer, input())
    assert [] = all_enqueued(worker: DeliveryWorker)
  end

  test "requires the configured Luft client and the explicit luft:app scope", ctx do
    root = Repo.get!(Token, ctx.session.oauth_grant_id)
    root |> Ecto.Changeset.change(scope: "openid") |> Repo.update!()
    assert {:error, :forbidden} = Push.dispatch_luft(ctx.user, ctx.bearer, input())
    root |> Ecto.Changeset.change(client_id: Tuist.OAuth.Clients.luft_client_id()) |> Repo.update!()
    assert {:error, :forbidden} = Push.dispatch_luft(ctx.user, ctx.bearer, input())
    assert [] = all_enqueued(worker: DeliveryWorker)
  end

  test "queued dispatch cannot follow a device rebound to another grant", ctx do
    assert :ok = Push.dispatch_luft(ctx.user, ctx.bearer, input())
    [job] = all_enqueued(worker: DeliveryWorker)
    {_bearer, replacement} = session(ctx.user, ctx.client_id)

    Tuist.Push.Installation
    |> Repo.get!(ctx.device.id)
    |> Ecto.Changeset.change(oauth_grant_id: replacement.oauth_grant_id)
    |> Repo.update!()

    # No HTTP expectation: delivery would fail if it attempted APNs.
    stub(Req, :post, fn _, _ -> flunk("must not send a rebound registration") end)
    assert :ok = perform_job(DeliveryWorker, job.args)
  end

  test "queued dispatch is suppressed after the owning grant is revoked", ctx do
    assert :ok = Push.dispatch_luft(ctx.user, ctx.bearer, input())
    [job] = all_enqueued(worker: DeliveryWorker)

    Token
    |> Repo.get!(ctx.session.oauth_grant_id)
    |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now())
    |> Repo.update!()

    stub(Req, :post, fn _, _ -> flunk("must not send after revocation") end)
    assert :ok = perform_job(DeliveryWorker, job.args)
  end

  defp input,
    do: %{
      "kind" => "alert",
      "notification_id" => "notification:revision:1",
      "payload" => %{
        "url" => "/luft/threads/example",
        "aps" => %{"alert" => %{"title" => "Your thread", "body" => "Replied."}}
      }
    }

  defp register(user, session) do
    {:ok, row} =
      Push.register(user, session, Ecto.UUID.generate(), %{
        platform: "ios",
        token: Base.encode16(:crypto.strong_rand_bytes(32)),
        environment: "production"
      })

    row
  end

  defp session(user, client_id) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client_id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client_id,
      sub: to_string(user.id),
      scope: "openid luft:app",
      redirect_uri: "https://luft.example/team/auth/callback"
    })

    {:ok, session} = Push.oauth_session(bearer, user, ["luft"])
    {bearer, session}
  end
end
