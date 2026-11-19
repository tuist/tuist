defmodule TuistWeb.API.ThreadRunnersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Runners
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    %{user: user, bearer: sign_in(user, Clients.luft_client_id())}
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

  test "Luft registers a runner whose secret connects it", %{conn: conn, bearer: bearer} do
    created =
      conn
      |> authorized(bearer)
      |> post("/api/me/thread-runners", %{name: "studio-macbook", platform: "macos"})
      |> json_response(201)

    assert %{"token" => "tgr_" <> _ = token, "online" => false} = created

    assert %{"requests" => []} =
             build_conn()
             |> authorized(token)
             |> post("/api/thread-runner/poll?wait_ms=0", %{terminal: true, folders: ["/src"]})
             |> json_response(200)

    assert %{"runners" => [%{"id" => id, "online" => true, "capabilities" => %{"terminal" => true}} = listed]} =
             build_conn() |> authorized(bearer) |> get("/api/me/thread-runners") |> json_response(200)

    refute Map.has_key?(listed, "token")

    assert build_conn() |> authorized(bearer) |> delete("/api/me/thread-runners/#{id}") |> response(204)
    assert build_conn() |> authorized(token) |> post("/api/thread-runner/poll?wait_ms=0", %{}) |> json_response(401)
  end

  test "a thread on an offline runner is refused with a reason Luft recognizes", %{
    conn: conn,
    user: user,
    bearer: bearer
  } do
    stub(Provider, :validate_model, fn _, _, _ -> :ok end)
    {:ok, runner, _token} = Runners.register(user, %{"name" => "macbook", "platform" => "macos"})

    assert %{"reason" => "runner_offline"} =
             conn
             |> authorized(bearer)
             |> post("/api/accounts/#{user.account.name}/threads", %{
               request_id: Ecto.UUID.generate(),
               content: "Look around",
               provider: "chatgpt",
               model: "m",
               runner_id: runner.id
             })
             |> json_response(409)
  end

  test "only Luft manages runners, and only a runner's secret polls", %{conn: conn, user: user, bearer: bearer} do
    app_bearer = sign_in(user, Clients.public!().id)
    assert conn |> authorized(app_bearer) |> get("/api/me/thread-runners") |> json_response(403)

    # A person's session is not a runner secret.
    assert build_conn() |> authorized(bearer) |> post("/api/thread-runner/poll?wait_ms=0", %{}) |> json_response(401)

    assert build_conn()
           |> authorized("tgr_unknown")
           |> post("/api/thread-runner/requests/#{Ecto.UUID.generate()}/response", %{ok: true})
           |> json_response(401)
  end
end
