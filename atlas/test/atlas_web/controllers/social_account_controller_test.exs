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
    assert params["scope"] == "tweet.read tweet.write users.read media.write offline.access"
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

  test "a LinkedIn Page admin connects the Page they administer as a brand account", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{scopes: ["gtm:write"]})
    page_id = "#{System.unique_integer([:positive])}"

    stub(Req, :request, fn opts ->
      case opts[:url] do
        "https://www.linkedin.com/oauth/v2/accessToken" ->
          refute Map.has_key?(opts[:form], "code_verifier")
          assert opts[:form]["client_secret"] == "test-secret"
          {:ok, %Req.Response{status: 200, body: %{"access_token" => "li-access", "expires_in" => 5_184_000}}}

        "https://api.linkedin.com/rest/organizationAcls" ->
          assert opts[:params][:role] == "ADMINISTRATOR"
          body = %{"elements" => [%{"organizationTarget" => "urn:li:organization:#{page_id}"}]}
          {:ok, %Req.Response{status: 200, body: body}}

        "https://api.linkedin.com/rest/organizations/" <> ^page_id ->
          {:ok, %Req.Response{status: 200, body: %{"localizedName" => "Tuist"}}}
      end
    end)

    # LinkedIn Pages are brands; a personal kind is refused before LinkedIn is asked.
    personal = get(conn, "/commercial/gtm/social/accounts/connect/personal?platform=linkedin")
    personal_state = personal |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    refused =
      get(recycle(personal), "/connections/linkedin/callback", %{"code" => "c", "state" => personal_state["state"]})

    assert Phoenix.Flash.get(refused.assigns.flash, :error)

    authorize = get(conn, "/commercial/gtm/social/accounts/connect/brand?platform=linkedin")
    location = URI.parse(redirected_to(authorize))
    params = URI.decode_query(location.query)
    assert location.host == "www.linkedin.com"
    assert params["scope"] == "rw_organization_admin r_organization_social"
    assert params["redirect_uri"] =~ "/connections/linkedin/callback"
    refute Map.has_key?(params, "code_challenge")

    # A LinkedIn state cannot complete through X's callback.
    wrong = get(recycle(authorize), "/connections/x/callback", %{"code" => "c", "state" => params["state"]})
    assert Phoenix.Flash.get(wrong.assigns.flash, :error)

    authorize = get(conn, "/commercial/gtm/social/accounts/connect/brand?platform=linkedin")
    params = authorize |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    callback = get(recycle(authorize), "/connections/linkedin/callback", %{"code" => "c", "state" => params["state"]})
    assert redirected_to(callback) == "/commercial/gtm/social/performance"

    assert %SocialAccount{handle: "Tuist", kind: "brand", connected_by_id: connected_by} =
             Repo.get_by!(SocialAccount, platform: "linkedin", external_id: page_id)

    assert connected_by == user.id
  end

  test "readers cannot start a connection, and X is no longer a personal connection", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["gtm:read"]})

    response = get(conn, ~p"/commercial/gtm/social/accounts/connect/brand")
    assert redirected_to(response) == "/commercial/gtm/social/performance"
    assert Phoenix.Flash.get(response.assigns.flash, :error)

    assert conn |> get("/connections/x/authorize") |> redirected_to() == "/settings/connections"
    assert conn |> get("/connections/linkedin/authorize") |> redirected_to() == "/settings/connections"
  end
end
