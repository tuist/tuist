defmodule TuistWeb.API.AIInferenceControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Accounts.AISubscriptions
  alias Tuist.FeatureFlags
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, client} = Clients.create_client(%{redirect_uris: ["https://luft.invalid/callback"], name: "inference"})
    stub(Clients, :luft_server_client_id, fn -> client.id end)
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    stub(AISubscriptions, :list, fn _ -> [%{provider: :claude, connected: true}] end)
    %{user: user, client: client, bearer: oauth(user, client, "luft:app")}
  end

  test "scoped Luft grants receive metadata only", %{bearer: bearer} do
    conn = request(bearer)
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert json_response(conn, 200) == %{
             "models" => [],
             "errors" => [
               %{"provider" => "claude", "code" => "unsupported_subscription"}
             ]
           }
  end

  test "missing, foreign, under-scoped and revoked credentials are rejected", %{user: user, client: client} do
    assert nil |> request() |> json_response(401)
    assert "invalid" |> request() |> json_response(401)
    assert user |> oauth(client, "") |> request() |> json_response(403)
    {:ok, foreign} = Clients.create_client(%{redirect_uris: ["https://foreign.invalid/callback"], name: "foreign"})
    assert user |> oauth(foreign, "luft:app") |> request() |> json_response(403)
    bearer = oauth(user, client, "luft:app")
    Token |> Repo.get_by!(value: bearer) |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
    # JWT subject authentication can succeed, but app admission authoritatively
    # rejects the revoked OAuth grant.
    assert bearer |> request() |> json_response(403)

    {:ok, {_, token}} =
      Accounts.create_account_token(%{account: user.account, scopes: ["account:cache:read"], name: "inference"})

    assert token |> request() |> json_response(403)
  end

  test "feature flag and current user state gate both actions", %{user: user, bearer: bearer} do
    stub(FeatureFlags, :luft_enabled?, fn _ -> false end)
    assert bearer |> request() |> json_response(404)
    assert bearer |> request(%{}) |> json_response(404)
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    Repo.update!(Ecto.Changeset.change(user, active: false))
    assert bearer |> request() |> json_response(401)
  end

  test "completion validates bodies and refuses Claude without credentials", %{bearer: bearer} do
    reject(AISubscriptions, :credentials, 2)
    assert %{"error" => %{"code" => "invalid_request"}} = bearer |> request(%{}) |> json_response(400)

    assert %{"error" => %{"code" => "unsupported_subscription"}} =
             bearer |> request(Map.put(params(), "provider", "claude")) |> json_response(403)
  end

  test "JSON endpoint accepts maximal Luft image turns but rejects oversized envelopes", %{bearer: bearer} do
    reject(AISubscriptions, :credentials, 2)
    image = "data:image/png;base64," <> Base.encode64(String.duplicate("x", 1_048_576))
    parts = List.duplicate(%{"type" => "image_url", "image_url" => %{"url" => image}}, 4)

    body =
      params()
      |> Map.put("provider", "claude")
      |> Map.put("messages", [
        %{"role" => "system", "content" => String.duplicate("p", 2_621_440)},
        %{"role" => "user", "content" => parts}
      ])
      |> Map.put("tools", List.duplicate(%{"type" => "function", "function" => %{"name" => "read"}}, 64))

    # Unsupported Claude is checked after validation and before any credentials.
    assert %{"error" => %{"code" => "unsupported_subscription"}} =
             bearer |> request(body) |> json_response(403)

    assert %{"error" => %{"code" => "invalid_request"}} =
             bearer
             |> request(
               Map.put(body, "messages", [
                 %{"role" => "user", "content" => String.duplicate("x", 8_388_608)}
               ])
             )
             |> json_response(400)
  end

  test "catalog and completion transport never return credentials or upstream error text", %{bearer: bearer} do
    provider_token = provider_token()
    stub(AISubscriptions, :credentials, fn _, :chatgpt -> {:ok, %{access_token: provider_token}} end)

    stub(Req, :get, fn opts ->
      assert {"authorization", "Bearer " <> provider_token} in opts[:headers]
      {:ok, %Req.Response{status: 200, body: %{"models" => [model()]}}}
    end)

    stub(AISubscriptions, :list, fn _ -> [%{provider: :chatgpt, connected: true}] end)
    catalog = request(bearer)

    assert json_response(catalog, 200) == %{
             "models" => [%{"provider" => "chatgpt", "id" => "selected-model", "name" => "Selected"}],
             "errors" => []
           }

    refute catalog.resp_body =~ provider_token
    refute catalog.resp_body =~ "private"

    stub(Req, :post, fn opts ->
      assert opts[:json]["model"] == "selected-model"
      {:ok, %Req.Response{status: 400, body: %{"error" => %{"code" => "model_not_found", "message" => provider_token}}}}
    end)

    conn = request(bearer, params())
    assert %{"error" => %{"code" => "model_not_found"}} = json_response(conn, 400)
    refute conn.resp_body =~ provider_token

    stub(Req, :post, fn _ ->
      {:ok,
       %Req.Response{
         status: 200,
         body:
           "data: " <>
             JSON.encode!(%{
               "type" => "response.completed",
               "response" => %{"id" => "reply", "model" => "selected-model", "output" => []}
             }) <> "\n\n"
       }}
    end)

    conn = request(bearer, params())

    assert %{"object" => "chat.completion", "choices" => [%{"message" => %{"role" => "assistant"}}]} =
             json_response(conn, 200)

    refute conn.resp_body =~ provider_token
  end

  test "revocation during refresh prevents any provider dispatch", %{bearer: bearer} do
    stub(AISubscriptions, :credentials, fn _, :chatgpt ->
      Token |> Repo.get_by!(value: bearer) |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
      {:ok, %{access_token: provider_token()}}
    end)

    reject(Req, :get, 1)
    reject(Req, :post, 1)
    assert %{"error" => %{"code" => "forbidden"}} = bearer |> request(params()) |> json_response(403)
  end

  test "unlisted models and credential failures never dispatch a completion", %{bearer: bearer} do
    reject(Req, :post, 1)
    stub(AISubscriptions, :credentials, fn _, :chatgpt -> {:error, :not_connected} end)
    assert %{"error" => %{"code" => "not_connected"}} = bearer |> request(params()) |> json_response(503)
    stub(AISubscriptions, :credentials, fn _, :chatgpt -> {:error, "private upstream failure"} end)
    assert %{"error" => %{"code" => "provider_auth"}} = bearer |> request(params()) |> json_response(502)

    stub(AISubscriptions, :credentials, fn _, :chatgpt -> {:ok, %{access_token: provider_token()}} end)
    stub(Req, :get, fn _ -> {:ok, %Req.Response{status: 200, body: %{"models" => []}}} end)
    assert %{"error" => %{"code" => "model_unavailable"}} = bearer |> request(params()) |> json_response(400)
  end

  test "deactivation while fetching catalog prevents completion dispatch", %{user: user, bearer: bearer} do
    stub(AISubscriptions, :credentials, fn _, :chatgpt -> {:ok, %{access_token: provider_token()}} end)

    stub(Req, :get, fn _ ->
      Repo.update!(Ecto.Changeset.change(user, disabled_at: DateTime.utc_now(:second)))
      {:ok, %Req.Response{status: 200, body: %{"models" => [model()]}}}
    end)

    reject(Req, :post, 1)
    assert %{"error" => %{"code" => "forbidden"}} = bearer |> request(params()) |> json_response(403)
  end

  defp request(bearer, body \\ nil) do
    {method, path} = if body, do: {:post, "chat/completions"}, else: {:get, "models"}
    conn = put_req_header(build_conn(), "content-type", "application/json")
    conn = if bearer, do: put_req_header(conn, "authorization", "Bearer " <> bearer), else: conn
    dispatch(conn, @endpoint, method, "/api/me/ai-subscriptions/#{path}", if(body, do: JSON.encode!(body)))
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

  defp params, do: %{"model" => "selected-model", "messages" => [%{"role" => "user", "content" => "Inspect"}]}

  defp model,
    do: %{
      "slug" => "selected-model",
      "display_name" => "Selected",
      "visibility" => "list",
      "supported_reasoning_levels" => [%{"effort" => "low"}],
      "instructions" => "private"
    }

  defp provider_token do
    claims = JSON.encode!(%{"https://api.openai.com/auth" => %{"chatgpt_account_id" => "personal-account"}})
    "header." <> Base.url_encode64(claims, padding: false) <> ".signature"
  end
end
