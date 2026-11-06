defmodule TuistWeb.API.ThreadsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Thread
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")
    %{user: user, token: token, path: "/api/accounts/#{user.account.name}/threads"}
  end

  test "requires bearer authentication and never caches denial", %{path: path} do
    conn = get(build_conn(), path)
    assert json_response(conn, 401)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "lists the user's private inbox without caching", %{path: path, token: token} do
    conn = request(token, path)
    assert json_response(conn, 200) == %{"threads" => [], "next_cursor" => nil}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "accepts native OAuth but not an unrelated OAuth client's grant", %{user: user, path: path} do
    client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> client_id end)
    native = oauth_token(user, Clients.public!())
    {:ok, other_client} = Clients.create_client(%{redirect_uris: ["https://example.com/callback"], name: "other"})
    other = oauth_token(user, other_client)
    assert native |> request(path) |> json_response(200)
    assert other |> request(path) |> json_response(403)
  end

  test "other administrators cannot read a conversation or its inbox entry", %{user: user, token: token} do
    organization = AccountsFixtures.organization_fixture(creator: user)
    other = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(other, organization, role: :admin)

    thread =
      Repo.insert!(%Thread{
        account_id: organization.account.id,
        owner_id: other.id,
        request_id: Ecto.UUID.generate(),
        request_hash: :crypto.hash(:sha256, "private"),
        title: "Private",
        provider: "chatgpt",
        model: "selected-model",
        goal: "Private"
      })

    path = "/api/accounts/#{organization.account.name}/threads"
    assert token |> request(path) |> json_response(200) == %{"threads" => [], "next_cursor" => nil}
    assert token |> request(path <> "/#{thread.id}") |> json_response(404)
  end

  test "does not reveal another account", %{token: token} do
    other = AccountsFixtures.user_fixture(preload: [:account])
    foreign = request(token, "/api/accounts/#{other.account.name}/threads")
    unknown = request(token, "/api/accounts/does-not-exist/threads")
    assert json_response(foreign, 404) == json_response(unknown, 404)
  end

  test "rejects shared credentials rather than treating their creator as owner", %{user: user, path: path} do
    {:ok, {_, token}} =
      Accounts.create_account_token(%{account: user.account, scopes: ["account:cache:read"], name: "threads"})

    assert token |> request(path) |> json_response(403)
  end

  test "malformed thread UUIDs are not server errors", %{token: token, path: path} do
    assert token |> request(path <> "/not-a-uuid") |> json_response(404)
  end

  test "a disabled AI flag hides the entire API", %{token: token, path: path} do
    stub(FeatureFlags, :ai_enabled?, fn _user -> false end)
    id = Ecto.UUID.generate()

    for {method, suffix} <- [
          {:get, ""},
          {:post, ""},
          {:get, "/repositories"},
          {:get, "/models"},
          {:get, "/#{id}"},
          {:patch, "/#{id}"},
          {:post, "/#{id}/messages"},
          {:post, "/#{id}/ship-preview"},
          {:post, "/#{id}/ship"},
          {:post, "/#{id}/ship-reconcile"}
        ] do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> dispatch(@endpoint, method, path <> suffix, %{})

      assert json_response(conn, 404) == %{"message" => "Not found."}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "repository discovery is routed before thread identifiers" do
    assert %{plug: TuistWeb.API.ThreadsController, plug_opts: :repositories} =
             Phoenix.Router.route_info(TuistWeb.Router, "GET", "/api/accounts/account/threads/repositories", "localhost")
  end

  test "model discovery is owner-authenticated and not cached", %{user: user, path: path, token: token} do
    expect(Provider, :models, fn actor ->
      assert actor.id == user.id
      %{models: [%{provider: "chatgpt", id: "selected-model", name: "Selected"}], errors: []}
    end)

    conn = request(token, path <> "/models")

    assert %{"models" => [%{"provider" => "chatgpt", "id" => "selected-model"}], "errors" => []} =
             json_response(conn, 200)

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert "invalid" |> request(path <> "/models") |> json_response(401)
  end

  test "body account handles cannot replace the path scope", %{token: token} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/accounts/does-not-exist/threads", %{account_handle: "another-account", content: "private"})

    assert json_response(conn, 404)
  end

  defp request(token, path), do: build_conn() |> put_req_header("authorization", "Bearer #{token}") |> get(path)

  defp oauth_token(user, client) do
    token = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: token,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    token
  end
end
