defmodule AtlasWeb.SocialAccountControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Connections.Config
  alias Atlas.GTM.SocialAccount
  alias Atlas.Repo

  setup do
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    :ok
  end

  test "someone with gtm:write connects an X account to Atlas through the registered callback", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{scopes: ["gtm:write"]})

    stub(Req, :request, fn opts ->
      case opts[:url] do
        "https://api.x.com/2/oauth2/token" ->
          assert opts[:form]["redirect_uri"] =~ "/connections/x/callback"
          {:ok, %Req.Response{status: 200, body: %{"access_token" => "x-access", "refresh_token" => "r"}}}

        "https://api.x.com/2/users/me" ->
          {:ok, %Req.Response{status: 200, body: %{"data" => %{"id" => "42", "username" => "pedro"}}}}
      end
    end)

    authorize = get(conn, ~p"/commercial/gtm/social/accounts/connect/personal")
    params = authorize |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["redirect_uri"] =~ "/connections/x/callback"
    assert params["scope"] == "tweet.read users.read offline.access"
    assert params["code_challenge_method"] == "S256"

    callback = get(recycle(authorize), "/connections/x/callback", %{"code" => "code", "state" => params["state"]})
    assert redirected_to(callback) == "/commercial/gtm/social/performance"

    assert %SocialAccount{handle: "@pedro", kind: "personal", connected_by_id: connected_by} =
             Repo.get_by!(SocialAccount, external_id: "42")

    assert connected_by == user.id

    # The state is single use.
    replay = get(recycle(callback), "/connections/x/callback", %{"code" => "code", "state" => params["state"]})
    assert Phoenix.Flash.get(replay.assigns.flash, :error)
  end

  test "readers cannot start a connection, and X is no longer a personal connection", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["gtm:read"]})

    response = get(conn, ~p"/commercial/gtm/social/accounts/connect/brand")
    assert redirected_to(response) == "/commercial/gtm/social/performance"
    assert Phoenix.Flash.get(response.assigns.flash, :error)

    assert conn |> get("/connections/x/authorize") |> redirected_to() == "/settings/connections"
  end
end
