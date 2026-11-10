defmodule Tuist.Push.Workers.DeliveryWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.APNs
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

    %{installation: installation, token: token, jwk: jwk, key_id: key_id, user: user, session: session}
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
    expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 410, body: ~s({"reason":"Unregistered"})}} end)

    assert :ok = perform(installation)
    assert %Installation{retired_reason: "rejected", token: nil} = Repo.get!(Installation, installation.id)
    assert Push.live_installations(installation.user_id) == []
  end

  test "retries on throttling and server errors without retiring", %{installation: installation} do
    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 429, body: ~s({"reason":"TooManyRequests"})}}
    end)

    assert {:error, "TooManyRequests"} = perform(installation)
    assert %Installation{retired_at: nil} = Repo.get!(Installation, installation.id)
  end

  test "gives up without retiring when APNs rejects the request itself", %{installation: installation} do
    expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 400, body: ~s({"reason":"TopicDisallowed"})}} end)

    assert {:cancel, "TopicDisallowed"} = perform(installation)
    assert %Installation{retired_at: nil} = Repo.get!(Installation, installation.id)
  end

  test "retires the registration when APNs says the device token is bad", %{installation: installation} do
    expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 400, body: ~s({"reason":"BadDeviceToken"})}} end)

    assert :ok = perform(installation)
    assert %Installation{retired_reason: "rejected", token: nil} = Repo.get!(Installation, installation.id)
  end

  test "reuses one provider token until APNs rejects it as expired", %{installation: installation} do
    test_pid = self()

    respond = fn response ->
      fn _url, opts ->
        send(test_pid, {:authorization, Map.new(opts[:headers])["authorization"]})
        {:ok, response}
      end
    end

    Req
    |> expect(:post, respond.(%Req.Response{status: 403, body: ~s({"reason":"ExpiredProviderToken"})}))
    |> expect(:post, 2, respond.(%Req.Response{status: 200, body: ""}))

    assert {:error, "ExpiredProviderToken"} = perform(installation)
    assert :ok = perform(installation)
    assert :ok = perform(installation)

    assert_received {:authorization, expired}
    assert_received {:authorization, renewed}
    assert_received {:authorization, reused}
    assert renewed != expired
    assert reused == renewed
  end

  test "concurrent deliveries on a cold node share one provider token", %{token: token} do
    test_pid = self()
    pem = Environment.apns_private_key()

    # Slow signing down so every delivery misses the cache before any finishes.
    stub(Environment, :apns_private_key, fn ->
      Process.sleep(50)
      pem
    end)

    stub(Req, :post, fn _url, opts ->
      send(test_pid, {:authorization, Map.new(opts[:headers])["authorization"]})
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    1..10
    |> Enum.map(fn _ -> Task.async(fn -> APNs.deliver("sandbox", token, @payload) end) end)
    |> Task.await_many()

    authorizations =
      for _ <- 1..10 do
        assert_received {:authorization, authorization}
        authorization
      end

    assert authorizations |> Enum.uniq() |> length() == 1
  end

  test "skips a registration retired after the job was queued", %{installation: installation} do
    :ok = Push.unregister(%Tuist.Accounts.User{id: installation.user_id}, installation.installation_id)
    reject(Req, :post, 2)

    assert :ok = perform(installation)
  end

  describe "Android" do
    setup %{user: user, session: session} do
      jwk = JOSE.JWK.generate_key({:rsa, 2048})
      {_, pem} = JOSE.JWK.to_pem(jwk)
      client_email = "fcm-#{System.unique_integer([:positive])}@tuist-app-push.iam.gserviceaccount.com"

      stub(Environment, :fcm_service_account, fn ->
        JSON.encode!(%{"project_id" => "tuist-app-push", "client_email" => client_email, "private_key" => pem})
      end)

      token = Base.encode64(:crypto.strong_rand_bytes(48))

      {:ok, installation} =
        Push.register(user, session, Ecto.UUID.generate(), %{platform: "android", token: token, environment: "production"})

      %{android: installation, android_token: token, rsa: jwk, client_email: client_email}
    end

    defp perform_android(installation),
      do:
        perform_job(DeliveryWorker, %{
          "registration_id" => installation.id,
          "payload" => %{"title" => "App", "body" => "Ready"}
        })

    defp expect_token_exchange(rsa, client_email) do
      expect(Req, :post, fn "https://oauth2.googleapis.com/token", opts ->
        assert opts[:form][:grant_type] == "urn:ietf:params:oauth:grant-type:jwt-bearer"

        assert {true,
                %JOSE.JWT{
                  fields: %{"iss" => ^client_email, "scope" => "https://www.googleapis.com/auth/firebase.messaging"}
                }, _} =
                 JOSE.JWT.verify_strict(JOSE.JWK.to_public(rsa), ["RS256"], opts[:form][:assertion])

        {:ok, %Req.Response{status: 200, body: %{"access_token" => "ya29.test", "expires_in" => 3599}}}
      end)
    end

    test "sends a data-only message with a service account access token", %{
      android: installation,
      android_token: token,
      rsa: rsa,
      client_email: client_email
    } do
      expect_token_exchange(rsa, client_email)

      expect(Req, :post, fn url, opts ->
        assert url == "https://fcm.googleapis.com/v1/projects/tuist-app-push/messages:send"
        assert Map.new(opts[:headers])["authorization"] == "Bearer ya29.test"

        assert opts[:json] == %{
                 "message" => %{
                   "token" => token,
                   "data" => %{"title" => "App", "body" => "Ready"},
                   "android" => %{"priority" => "HIGH", "ttl" => "86400s"}
                 }
               }

        {:ok, %Req.Response{status: 200, body: %{"name" => "projects/tuist-app-push/messages/1"}}}
      end)

      assert :ok = perform_android(installation)
    end

    test "retires the registration when FCM says the token is unregistered", %{
      android: installation,
      rsa: rsa,
      client_email: client_email
    } do
      expect_token_exchange(rsa, client_email)

      expect(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{
             "error" => %{
               "status" => "NOT_FOUND",
               "details" => [
                 %{"@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode" => "UNREGISTERED"}
               ]
             }
           }
         }}
      end)

      assert :ok = perform_android(installation)
      assert %Installation{retired_reason: "rejected", token: nil} = Repo.get!(Installation, installation.id)
    end

    test "fetches a new access token after FCM rejects the cached one", %{
      android: installation,
      rsa: rsa,
      client_email: client_email
    } do
      expect_token_exchange(rsa, client_email)

      expect(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => %{"status" => "UNAUTHENTICATED"}}}}
      end)

      assert {:error, "UNAUTHENTICATED"} = perform_android(installation)
      assert %Installation{retired_at: nil} = Repo.get!(Installation, installation.id)

      expect_token_exchange(rsa, client_email)
      expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 200, body: %{}}} end)

      assert :ok = perform_android(installation)
    end
  end
end
