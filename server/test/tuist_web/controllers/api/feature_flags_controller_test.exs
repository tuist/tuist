defmodule TuistWeb.API.FeatureFlagsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

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

  defp flags(bearer) do
    build_conn() |> put_req_header("authorization", "Bearer #{bearer}") |> get("/api/me/feature-flags")
  end

  test "lists the flags enabled for the signed-in user", %{bearer: bearer} do
    conn = flags(bearer)

    assert json_response(conn, 200) == %{"enabled" => ["ai"]}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "accepts user sessions", %{user: user} do
    {:ok, bearer, _claims} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")

    assert bearer |> flags() |> json_response(200) == %{"enabled" => ["ai"]}
  end

  test "rejects account tokens and other OAuth clients", %{user: user} do
    {:ok, other_client} = Clients.create_client(%{redirect_uris: ["https://example.com/callback"], name: "other"})

    {:ok, {_, account_token}} =
      Accounts.create_account_token(%{account: user.account, scopes: ["account:cache:read"], name: "flags-test-token"})

    assert user |> sign_in(other_client) |> flags() |> json_response(403)
    assert account_token |> flags() |> json_response(403)
    assert build_conn() |> get("/api/me/feature-flags") |> json_response(401)
  end
end
