defmodule Tuist.Entire.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Entire.Client, as: Entire
  alias Tuist.KeyValueStore

  setup context do
    cache = :"#{__MODULE__}.#{context.test}"
    jwks_cache = :"#{cache}.jwks"
    start_supervised!({Cachex, name: cache})
    start_supervised!(Supervisor.child_spec({Cachex, name: jwks_cache}, id: jwks_cache))
    key = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, public} = JOSE.JWK.to_public_map(key)
    {_, pem} = JOSE.JWK.to_pem(key)
    public = Map.put(public, "kid", "entire-test")

    stub(Entire, :config, fn ->
      [slug: "tuist-ci", private_key: pem, delivery_jwks_url: "https://delivery.entire.io/.well-known/jwks.json"]
    end)

    stub(KeyValueStore, :get, fn cache_key ->
      Mimic.call_original(KeyValueStore, :get, [cache_key, [cache: cache]])
    end)

    stub(KeyValueStore, :put, fn cache_key, value, opts ->
      Mimic.call_original(KeyValueStore, :put, [cache_key, value, Keyword.put(opts, :cache, cache)])
    end)

    stub(KeyValueStore, :get_or_update, fn cache_key, opts, fetch ->
      target =
        case Keyword.get(opts, :cache, :tuist) do
          :tuist -> cache
          :entire_jwks -> jwks_cache
        end

      Mimic.call_original(KeyValueStore, :get_or_update, [cache_key, Keyword.put(opts, :cache, target), fetch])
    end)

    stub(Req, :get, fn _ -> {:ok, %Req.Response{status: 200, body: %{"keys" => [public]}}} end)
    %{key: key, public: public, cache: cache, jwks_cache: jwks_cache}
  end

  test "verifies receipt identity, audience, expiry and signed state", %{key: key} do
    claims =
      claims(%{
        "iss" => "https://eu.auth.entire.io",
        "aud" => ["other", "urn:entire:plugin:tuist-ci"],
        "plugin_id" => "tuist-ci",
        "installation_id" => "ins_one",
        "state" => "state-one"
      })

    token = sign(key, claims, "entire-install-receipt+jwt")
    assert {:ok, %{"installation_id" => "ins_one"}} = Entire.verify_receipt(token, "state-one")
    assert {:error, :invalid_receipt} = Entire.verify_receipt(token, "state-two")

    for changes <- [
          %{"aud" => "tuist-ci"},
          %{"exp" => System.system_time(:second) - 120},
          %{"plugin_id" => "someone-else"},
          %{"sub" => "ins_other"},
          %{"iss" => "https://eu.auth.entire.io.attacker.test"}
        ] do
      assert {:error, :invalid_receipt} =
               Entire.verify_receipt(sign(key, Map.merge(claims, changes), "entire-install-receipt+jwt"), "state-one")
    end
  end

  test "does not fetch a receipt issuer outside the explicit Core allowlist", %{key: key} do
    reject(&Req.get/1)

    token =
      sign(
        key,
        claims(%{"iss" => "https://attacker.test", "aud" => "urn:entire:plugin:tuist-ci"}),
        "entire-install-receipt+jwt"
      )

    assert {:error, :invalid_receipt} = Entire.verify_receipt(token, "state")
  end

  test "binds delivery signatures to exact bytes and the slug audience", %{key: key} do
    body = JSON.encode!(%{delivery_id: "delivery-1", installation_id: "ins_one", plugin_id: "tuist-ci"})
    digest = Base.url_encode64(:crypto.hash(:sha256, body), padding: false)

    claims =
      claims(%{"iss" => "https://us-east-2.entire-ci-webhooks.entire.io", "aud" => "tuist-ci", "body_sha256" => digest})

    token = sign(key, claims)
    assert {:ok, %{"delivery_id" => "delivery-1"}, "jti-one"} = Entire.verify_delivery(token, body)
    assert {:error, :invalid_delivery} = Entire.verify_delivery(token, body <> " ")

    assert {:error, :invalid_delivery} =
             Entire.verify_delivery(sign(key, Map.put(claims, "aud", "urn:entire:plugin:tuist-ci")), body)

    assert {:error, :invalid_delivery} =
             Entire.verify_delivery(sign(JOSE.JWK.generate_key({:okp, :Ed25519}), claims), body)
  end

  test "reports unavailable signing keys as retryable", %{key: key} do
    expect(Req, :get, fn _ -> {:error, :closed} end)
    token = sign(key, claims(%{"iss" => "https://eu.auth.entire.io"}), "entire-install-receipt+jwt")

    for _ <- 1..2 do
      assert {:error, :unavailable} = Entire.verify_receipt(token, "state")
    end
  end

  test "refreshes keys on rotation without caching a missing key", %{key: key, public: public} do
    stub(KeyValueStore, :get, fn _ -> {:ok, []} end)
    expect(Req, :get, fn _ -> {:ok, %Req.Response{status: 200, body: %{"keys" => [public]}}} end)

    token =
      sign(
        key,
        claims(%{
          "iss" => "https://eu.auth.entire.io",
          "aud" => "urn:entire:plugin:tuist-ci",
          "plugin_id" => "tuist-ci",
          "installation_id" => "ins_one",
          "state" => "state"
        }),
        "entire-install-receipt+jwt"
      )

    assert {:ok, _} = Entire.verify_receipt(token, "state")
  end

  test "bounds unknown-key traffic while accepting known keys and retrying rotation", context do
    {:ok, requests} = Agent.start_link(fn -> 0 end)
    rotated_key = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, rotated_public} = JOSE.JWK.to_public_map(rotated_key)
    rotated_public = Map.put(rotated_public, "kid", "rotated")
    {:ok, remote_keys} = Agent.start_link(fn -> [context.public] end)

    stub(Req, :get, fn _ ->
      Agent.update(requests, &(&1 + 1))
      {:ok, %Req.Response{status: 200, body: %{"keys" => Agent.get(remote_keys, & &1)}}}
    end)

    {known, body} = delivery(context.key, "entire-test")
    assert {:ok, _, _} = Entire.verify_delivery(known, body)

    for kid <- 1..10 do
      {unknown, ^body} = delivery(rotated_key, "unknown-#{kid}")
      assert {:error, _} = Entire.verify_delivery(unknown, body)
    end

    # The HTTP budget is per issuer, not per attacker-controlled key ID.
    assert Agent.get(requests, & &1) == 1
    assert {:ok, _, _} = Entire.verify_delivery(known, body)

    Agent.update(remote_keys, fn _ -> [rotated_public] end)
    {rotated, ^body} = delivery(rotated_key, "rotated")
    assert {:error, :unavailable} = Entire.verify_delivery(rotated, body)

    # Evict the cache to exercise the next permitted refresh without sleeping.
    Cachex.clear(context.cache)
    Cachex.clear(context.jwks_cache)
    assert {:ok, _, _} = Entire.verify_delivery(rotated, body)
    assert Agent.get(requests, & &1) == 2
  end

  test "slow signing-key refreshes do not block unrelated cached lookups", %{key: key, public: public} do
    owner = self()
    cache_key = [__MODULE__, :unrelated_project]
    assert :cached_project = KeyValueStore.get_or_update(cache_key, [], fn -> :cached_project end)

    stub(Req, :get, fn _ ->
      send(owner, {:fetching_keys, self()})

      receive do
        :release_refresh -> {:ok, %Req.Response{status: 200, body: %{"keys" => [public]}}}
      after
        5_000 -> {:error, :timeout}
      end
    end)

    {token, body} = delivery(key, "entire-test")
    verification = Task.async(fn -> Entire.verify_delivery(token, body) end)
    assert_receive {:fetching_keys, fetcher}, 1_000

    lookup =
      Task.async(fn ->
        result = KeyValueStore.get_or_update(cache_key, [], fn -> :unexpected_miss end)
        send(owner, {:cached_lookup, result})
        result
      end)

    try do
      assert_receive {:cached_lookup, :cached_project}, 1_000
    after
      send(fetcher, :release_refresh)
      assert {:ok, _, _} = Task.await(verification)
      assert :cached_project = Task.await(lookup)
    end
  end

  test "coalesces concurrent refreshes for a newly rotated signing key", %{key: key, public: public} do
    owner = self()
    {:ok, requests} = Agent.start_link(fn -> 0 end)

    stub(KeyValueStore, :get, fn _ ->
      send(owner, :read_cached_keys)
      {:ok, []}
    end)

    stub(Req, :get, fn _ ->
      Agent.update(requests, &(&1 + 1))
      send(owner, {:fetching_keys, self()})

      receive do
        :release_refresh -> {:ok, %Req.Response{status: 200, body: %{"keys" => [public]}}}
      after
        5_000 -> {:error, :timeout}
      end
    end)

    {token, body} = delivery(key, "entire-test")
    tasks = for _ <- 1..10, do: Task.async(fn -> Entire.verify_delivery(token, body) end)

    for _ <- tasks, do: assert_receive(:read_cached_keys, 1_000)
    assert_receive {:fetching_keys, fetcher}, 1_000
    Enum.each(tasks, &send(&1.pid, :release_refresh))
    send(fetcher, :release_refresh)

    for task <- tasks, do: assert({:ok, _, _} = Task.await(task))
    assert Agent.get(requests, & &1) == 1
  end

  test "caches tokens separately by installation, repository and exact permissions" do
    scopes = [
      {%{remote_id: "ins_one"}, "repo_one", %{"contents" => "read"}, "one-contents"},
      {%{remote_id: "ins_one"}, "repo_one", %{"contents" => "read", "discussions" => "read"}, "one-discussions-read"},
      {%{remote_id: "ins_one"}, "repo_one", %{"contents" => "read", "discussions" => "write"}, "one-discussions"},
      {%{remote_id: "ins_one"}, "repo_two", %{"contents" => "read", "discussions" => "write"}, "two-discussions"},
      {%{remote_id: "ins_other"}, "repo_one", %{"contents" => "read", "discussions" => "write"}, "other-installation"}
    ]

    stub(Req, :request, fn opts ->
      {_, _, _, token} =
        Enum.find(scopes, fn {installation, repository_id, permissions, _token} ->
          String.ends_with?(opts[:url], "/#{installation.remote_id}/access-tokens") and
            opts[:json] == %{repository_id: repository_id, permissions: permissions}
        end)

      {:ok, %Req.Response{status: 200, body: %{"token" => token}}}
    end)

    for {installation, repository_id, permissions, expected} <- scopes do
      assert {:ok, ^expected} = Entire.access_token(installation, repository_id, permissions)
    end

    # Cached tokens must retain their exact scope even when Core is unavailable.
    stub(Req, :request, fn _ -> {:error, :closed} end)

    for {installation, repository_id, permissions, expected} <- Enum.reverse(scopes) do
      assert {:ok, ^expected} = Entire.access_token(installation, repository_id, permissions)
    end
  end

  defp delivery(key, kid) do
    body = JSON.encode!(%{delivery_id: "delivery-rotation", installation_id: "ins_one", plugin_id: "tuist-ci"})
    digest = Base.url_encode64(:crypto.hash(:sha256, body), padding: false)

    claims =
      claims(%{"iss" => "https://delivery.entire.io", "aud" => "tuist-ci", "body_sha256" => digest})

    {sign(key, claims, "JWT", kid), body}
  end

  defp claims(extra) do
    now = System.system_time(:second)
    Map.merge(%{"iat" => now - 30, "exp" => now + 270, "jti" => "jti-one"}, extra)
  end

  defp sign(key, claims, typ \\ "JWT", kid \\ "entire-test") do
    {_, token} =
      key |> JOSE.JWT.sign(%{"alg" => "EdDSA", "kid" => kid, "typ" => typ}, claims) |> JOSE.JWS.compact()

    token
  end
end
