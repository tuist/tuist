defmodule Tuist.Push.Workers.DeliveryWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.Installation
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @payload %{"aps" => %{"alert" => %{"title" => "App", "body" => "Version 1 is ready to install."}}}

  setup do
    app_client_id = Ecto.UUID.generate()
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = JOSE.JWK.to_pem(jwk)
    key_id = "K#{System.unique_integer([:positive])}"

    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    stub(Environment, :apns_key_id, fn -> key_id end)
    stub(Environment, :apns_team_id, fn -> "TEAM123456" end)
    stub(Environment, :apns_topic, fn -> "dev.tuist.app" end)
    stub(Environment, :apns_private_key, fn -> pem end)

    user = AccountsFixtures.user_fixture()
    client = Clients.public!()
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    {:ok, session} = Push.oauth_session(bearer, user)
    token = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

    {:ok, installation} =
      Push.register(user, session, Ecto.UUID.generate(), %{platform: "ios", token: token, environment: "sandbox"})

    %{installation: installation, token: token, jwk: jwk, key_id: key_id}
  end

  defp perform(installation),
    do: perform_job(DeliveryWorker, %{"registration_id" => installation.id, "payload" => @payload})

  test "posts a signed alert to the registration's APNs environment", %{
    installation: installation,
    token: token,
    jwk: jwk,
    key_id: key_id
  } do
    expect(Req, :post, fn url, opts ->
      assert url == "https://api.sandbox.push.apple.com/3/device/#{token}"
      assert opts[:json] == @payload
      headers = Map.new(opts[:headers])
      assert headers["apns-topic"] == "dev.tuist.app"
      assert headers["apns-push-type"] == "alert"

      "bearer " <> jwt = headers["authorization"]

      assert {true, %JOSE.JWT{fields: %{"iss" => "TEAM123456"}}, %JOSE.JWS{fields: %{"kid" => ^key_id}}} =
               JOSE.JWT.verify_strict(JOSE.JWK.to_public(jwk), ["ES256"], jwt)

      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    assert :ok = perform(installation)
  end

  test "retires the registration when APNs says the token is gone", %{installation: installation} do
    expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 410, body: %{"reason" => "Unregistered"}}} end)

    assert :ok = perform(installation)
    assert %Installation{retired_reason: "rejected", token: nil} = Repo.get!(Installation, installation.id)
    assert Push.live_installations(installation.user_id) == []
  end

  test "retries on throttling and server errors without retiring", %{installation: installation} do
    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 429, body: %{"reason" => "TooManyRequests"}}}
    end)

    assert {:error, "TooManyRequests"} = perform(installation)
    assert %Installation{retired_at: nil} = Repo.get!(Installation, installation.id)
  end

  test "gives up without retiring when APNs rejects the request itself", %{installation: installation} do
    expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 400, body: %{"reason" => "TopicDisallowed"}}} end)

    assert {:cancel, "TopicDisallowed"} = perform(installation)
    assert %Installation{retired_at: nil} = Repo.get!(Installation, installation.id)
  end

  test "skips a registration retired after the job was queued", %{installation: installation} do
    :ok = Push.unregister(%Tuist.Accounts.User{id: installation.user_id}, installation.installation_id)
    reject(Req, :post, 2)

    assert :ok = perform(installation)
  end
end
