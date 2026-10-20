defmodule TuistWeb.API.OIDCWorkloadControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Guardian
  alias Tuist.KeyValueStore
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.OIDC
  alias Tuist.OIDC.JWKSClient
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.TooManyRequestsError
  alias TuistWeb.RateLimit

  @attrs %{
    name: "Production",
    issuer: "https://id.example/tenant",
    jwks_url: "https://keys.example/jwks",
    audience: "tuist",
    claims: %{"sub" => "service:production"}
  }

  setup_all do
    %{key: JOSE.JWK.generate_key({:rsa, 2048}), other_key: JOSE.JWK.generate_key({:rsa, 2048})}
  end

  setup %{key: key} do
    project = ProjectsFixtures.project_fixture(preload: [:account])
    {:ok, policy} = Projects.create_oidc_trust_policy(project, @attrs)
    stub(KeyValueStore, :get_or_update, fn _, _, fetch -> fetch.() end)
    stub(SSRFGuard, :pin, fn url -> {:ok, url, "keys.example"} end)
    parent = self()

    stub(JWKSClient, :get, fn url, opts ->
      send(parent, {:jwks_fetch, url, opts})
      {:ok, %{status: 200, body: jwks(key)}}
    end)

    %{project: project, account: project.account.name, policy: policy}
  end

  test "issues one-hour CI access only for explicitly trusted projects", %{
    conn: conn,
    key: key,
    project: project,
    account: account
  } do
    second = ProjectsFixtures.project_fixture(account: project.account)
    {:ok, _} = Projects.create_oidc_trust_policy(second, @attrs)
    ProjectsFixtures.project_fixture(account: project.account, vcs_connection: [repository_full_handle: "tuist/tuist"])
    response = conn |> exchange(sign(key), String.upcase(account)) |> json_response(:ok)
    assert response["expires_in"] == 3600
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert Enum.sort(claims["project_ids"]) == Enum.sort([project.id, second.id])
    assert claims["sub"] == to_string(project.account.id)
    assert claims["scopes"] == ["ci"]
    expected_url = @attrs.jwks_url
    assert_receive {:jwks_fetch, ^expected_url, opts}
    assert opts[:redirect] == false
    assert opts[:retry] == false
    assert opts[:decode_body] == false
    assert opts[:connect_options][:timeout] == 5_000
    assert opts[:connect_options][:hostname] == "keys.example"
    refute_receive {:jwks_fetch, _, _}
  end

  test "requires an account before any policy or network lookup", %{conn: conn, key: key} do
    assert conn |> exchange(sign(key), nil) |> json_response(:bad_request) |> Map.fetch!("message") =~
             "TUIST_OIDC_ACCOUNT"

    refute_receive {:jwks_fetch, _, _}
  end

  test "unknown account, wrong subject and absent policy use the same rejection without fetching", %{
    conn: conn,
    key: key,
    account: account,
    project: project,
    policy: policy
  } do
    first = conn |> exchange(sign(key), "unknown-account") |> json_response(:unauthorized)
    second = conn |> exchange(sign(key, %{"sub" => "other"}), account) |> json_response(:unauthorized)
    {:ok, _} = Projects.delete_oidc_trust_policy(project, policy.id)
    third = conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    assert first == second and second == third
    assert first["message"] == "OIDC token signature verification failed"
    refute_receive {:jwks_fetch, _, _}
  end

  test "repository claims cannot authorize a custom workload", %{conn: conn, key: key, account: account} do
    ProjectsFixtures.project_fixture(vcs_connection: [repository_full_handle: "tuist/tuist"])

    assert conn
           |> exchange(sign(key, %{"sub" => "untrusted", "repository" => "tuist/tuist"}), account)
           |> json_response(:unauthorized)

    refute_receive {:jwks_fetch, _, _}
  end

  test "foreign policies never supply keys or poison the selected account", %{
    conn: conn,
    key: key,
    other_key: other,
    account: account,
    project: project
  } do
    foreign = ProjectsFixtures.project_fixture(preload: [:account])
    {:ok, _} = Projects.create_oidc_trust_policy(foreign, %{@attrs | jwks_url: "https://attacker.example/keys"})
    parent = self()

    stub(JWKSClient, :get, fn url, _ ->
      send(parent, {:key_url, url})
      {:ok, %{status: 200, body: jwks(if(url == @attrs.jwks_url, do: key, else: other))}}
    end)

    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["project_ids"] == [project.id]
    expected_url = @attrs.jwks_url
    assert_receive {:key_url, ^expected_url}
    refute_receive {:key_url, "https://attacker.example/keys"}
    assert conn |> exchange(sign(other), account) |> json_response(:unauthorized)
  end

  test "same-account projects cannot borrow another policy's key verification", %{
    conn: conn,
    key: key,
    other_key: other,
    account: account,
    project: project
  } do
    sibling = ProjectsFixtures.project_fixture(account: project.account)
    {:ok, _} = Projects.create_oidc_trust_policy(sibling, %{@attrs | jwks_url: "https://other.example/keys"})

    stub(JWKSClient, :get, fn url, _ ->
      {:ok, %{status: 200, body: jwks(if(url == @attrs.jwks_url, do: key, else: other))}}
    end)

    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["project_ids"] == [project.id]
  end

  for {claim, value} <- [
        {"aud", "other"},
        {"aud", nil},
        {"aud", ["other"]},
        {"aud", ["tuist", 123]},
        {"exp", 0},
        {"exp", nil},
        {"nbf", 99_999_999_999},
        {"nbf", "invalid"},
        {"iss", "https://other.example"},
        {"sub", nil},
        {"sub", ["service:production"]}
      ] do
    test "rejects #{claim}=#{inspect(value)}", %{conn: conn, key: key, account: account} do
      assert conn
             |> exchange(sign(key, %{unquote(claim) => unquote(Macro.escape(value))}), account)
             |> json_response(:unauthorized)
    end
  end

  test "accepts audience lists and precisely bounded nbf skew", %{conn: conn, key: key, account: account} do
    now = DateTime.to_unix(DateTime.utc_now())
    stub(DateTime, :utc_now, fn -> DateTime.from_unix!(now) end)
    assert conn |> exchange(sign(key, %{"aud" => ["other", "tuist"], "nbf" => now + 60}), account) |> json_response(:ok)
    assert conn |> exchange(sign(key, %{"nbf" => now + 61}), account) |> json_response(:unauthorized)
  end

  test "Fly IDs are ordinary exact claims in the generic flow", %{
    conn: conn,
    key: key,
    account: account,
    project: project
  } do
    {:ok, _} =
      Projects.create_oidc_trust_policy(project, %{
        @attrs
        | name: "Fly.io",
          issuer: "https://oidc.fly.io/my-org",
          jwks_url: "https://oidc.fly.io/my-org/.well-known/jwks",
          claims: %{"org_id" => "123", "app_id" => "456"}
      })

    assert conn
           |> exchange(sign(key, %{"iss" => "https://oidc.fly.io/my-org", "org_id" => "123", "app_id" => "456"}), account)
           |> json_response(:ok)

    assert conn
           |> exchange(sign(key, %{"iss" => "https://oidc.fly.io/my-org", "org_id" => 123, "app_id" => "456"}), account)
           |> json_response(:unauthorized)
  end

  test "integer, boolean and string claim types remain distinct", %{
    conn: conn,
    key: key,
    account: account,
    project: project
  } do
    {:ok, _} =
      Projects.create_oidc_trust_policy(project, %{@attrs | name: "Typed", claims: %{"id" => 123, "protected" => true}})

    for value <- ["123", 123.0, [123]] do
      assert conn
             |> exchange(sign(key, %{"sub" => "different", "id" => value, "protected" => true}), account)
             |> json_response(:unauthorized)
    end

    assert conn
           |> exchange(sign(key, %{"sub" => "different", "id" => 123, "protected" => true}), account)
           |> json_response(:ok)
  end

  test "deletion and key-URL mutation are rechecked after verification", %{
    key: key,
    account: account,
    project: project,
    policy: policy
  } do
    assert {:ok, identity} = OIDC.claims(sign(key), account)
    Repo.update!(Ecto.Changeset.change(policy, jwks_url: "https://different.example/keys"))
    assert [] == Projects.projects_by_oidc_grants(identity)
    {:ok, _} = Projects.delete_oidc_trust_policy(project, policy.id)
    assert [] == Projects.projects_by_oidc_grants(identity)
  end

  test "bounds distinct JWKS URLs before any fetch", %{conn: conn, key: key, account: account, project: project} do
    for i <- 1..2 do
      {:ok, _} =
        Projects.create_oidc_trust_policy(project, %{
          @attrs
          | name: "Policy #{i}",
            jwks_url: "https://keys#{i}.example/jwks"
        })
    end

    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    refute_receive {:jwks_fetch, _, _}
  end

  test "bounds matching candidates across projects before any fetch", %{
    conn: conn,
    key: key,
    account: account,
    project: project
  } do
    for i <- 1..19 do
      {:ok, _} = Projects.create_oidc_trust_policy(project, %{@attrs | name: "Policy #{i}"})
    end

    sibling = ProjectsFixtures.project_fixture(account: project.account)
    {:ok, _} = Projects.create_oidc_trust_policy(sibling, @attrs)
    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    refute_receive {:jwks_fetch, _, _}
  end

  test "SSRF protection pins the connection and refuses private or rebound hosts", %{
    conn: conn,
    key: key,
    account: account
  } do
    stub(SSRFGuard, :pin, fn _ -> {:error, :private_ip_resolved} end)
    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    refute_receive {:jwks_fetch, _, _}
  end

  test "real SSRF guard rejects loopback and metadata addresses" do
    # Initialize the Mimic original before checking literal addresses.
    assert {:error, _} = Mimic.call_original(SSRFGuard, :pin, ["https://127.0.0.1/keys"])
    assert {:error, _} = Mimic.call_original(SSRFGuard, :pin, ["https://169.254.169.254/keys"])
  end

  for body <- ["not json", String.duplicate("a", 65_537), "{\"keys\":[]}", ~s({"keys":[{"kty":"oct","k":"c2VjcmV0"}]})] do
    test "refuses invalid, oversized or unusable JWKS #{String.slice(body, 0, 25)}", %{
      conn: conn,
      key: key,
      account: account
    } do
      stub(JWKSClient, :get, fn _, _ -> {:ok, %{status: 200, body: unquote(body)}} end)
      assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    end
  end

  test "streaming aborts when the response limit is crossed", %{conn: conn, key: key, account: account} do
    parent = self()

    stub(JWKSClient, :get, fn _, opts ->
      response = %{status: 200, headers: [], body: String.duplicate("a", 65_530)}
      result = opts[:into].({:data, "too much data"}, {nil, response})
      send(parent, {:bounded_result, result})
      {:ok, %{status: 200, body: :response_too_large}}
    end)

    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    assert_receive {:bounded_result, {:halt, {_, %{body: :response_too_large}}}}
  end

  test "redirects and transport failures fail closed", %{conn: conn, key: key, account: account} do
    stub(JWKSClient, :get, fn _, _ -> {:error, {:unexpected_status, 302}} end)
    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    stub(JWKSClient, :get, fn _, _ -> {:error, %Mint.TransportError{reason: :timeout}} end)
    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
  end

  test "successes are cached but fetch errors are not, and deletion still revokes", %{
    conn: conn,
    key: key,
    account: account,
    policy: policy,
    project: project
  } do
    policy = Repo.update!(Ecto.Changeset.change(policy, jwks_url: "https://keys.example/#{project.id}"))

    stub(KeyValueStore, :get_or_update, fn cache_key, opts, fetch ->
      Mimic.call_original(KeyValueStore, :get_or_update, [cache_key, opts, fetch])
    end)

    parent = self()

    stub(JWKSClient, :get, fn _, _ ->
      send(parent, :failed_fetch)
      {:error, %Mint.TransportError{reason: :timeout}}
    end)

    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    assert_receive :failed_fetch

    stub(JWKSClient, :get, fn _, _ ->
      send(parent, :successful_fetch)
      {:ok, %{status: 200, body: jwks(key)}}
    end)

    token = sign(key)
    assert conn |> exchange(token, account) |> json_response(:ok)
    assert_receive :successful_fetch
    assert conn |> exchange(token, account) |> json_response(:ok)
    refute_receive :successful_fetch
    {:ok, _} = Projects.delete_oidc_trust_policy(project, policy.id)
    assert conn |> exchange(token, account) |> json_response(:unauthorized)
    refute_receive :successful_fetch
  end

  test "rejects critical headers and symmetric or unsigned algorithms before fetching", %{
    conn: conn,
    key: key,
    account: account
  } do
    assert conn |> exchange(sign(key, %{}, %{"crit" => ["custom"]}), account) |> json_response(:unauthorized)
    symmetric = JOSE.JWK.from_oct("secret")
    assert conn |> exchange(sign(symmetric, %{}, %{"alg" => "HS256"}), account) |> json_response(:unauthorized)
    [header, payload, signature] = String.split(sign(key), ".")

    header =
      header
      |> Base.url_decode64!(padding: false)
      |> JSON.decode!()
      |> Map.put("alg", "none")
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    assert conn |> exchange(Enum.join([header, payload, signature], "."), account) |> json_response(:unauthorized)
    refute_receive {:jwks_fetch, _, _}
  end

  test "requires the declared key algorithm and signing use to match", %{conn: conn, key: key, account: account} do
    for overrides <- [%{"alg" => "RS512"}, %{"use" => "enc"}, %{"key_ops" => ["encrypt"]}, %{"n" => "invalid"}] do
      stub(JWKSClient, :get, fn _, _ -> {:ok, %{status: 200, body: jwks(key, overrides)}} end)
      assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    end
  end

  test "missing kid requires exactly one eligible key", %{conn: conn, key: key, other_key: other, account: account} do
    token = sign(key, %{}, %{"kid" => nil})
    assert conn |> exchange(token, account) |> json_response(:ok)

    stub(JWKSClient, :get, fn _, _ ->
      %{"keys" => [first]} = JSON.decode!(jwks(key))
      %{"keys" => [second]} = JSON.decode!(jwks(other))
      {:ok, %{status: 200, body: JSON.encode!(%{"keys" => [first, second]})}}
    end)

    assert conn |> exchange(token, account) |> json_response(:unauthorized)
  end

  test "supports elliptic curve identity providers", %{conn: conn, account: account} do
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    stub(JWKSClient, :get, fn _, _ -> {:ok, %{status: 200, body: jwks(key)}} end)
    assert conn |> exchange(sign(key, %{}, %{"alg" => "ES256"}), account) |> json_response(:ok)
  end

  test "rejects oversized tokens and non-string issuers without crashing", %{conn: conn, key: key, account: account} do
    for token <- [String.duplicate("x", 16_385), sign(key, %{"iss" => %{}}), sign(key, %{"iss" => 123})] do
      assert conn |> exchange(token, account) |> json_response(:unauthorized)
    end

    refute_receive {:jwks_fetch, _, _}
  end

  test "supports the RSA/PSS and Ed25519 signing algorithms", %{conn: conn, key: rsa, account: account} do
    for algorithm <- ~w(RS256 RS384 RS512 PS256 PS384 PS512 EdDSA) do
      key = if algorithm == "EdDSA", do: JOSE.JWK.generate_key({:okp, :Ed25519}), else: rsa
      stub(JWKSClient, :get, fn _, _ -> {:ok, %{status: 200, body: jwks(key)}} end)
      assert conn |> exchange(sign(key, %{}, %{"alg" => algorithm}), account) |> json_response(:ok)
    end
  end

  test "rejects unknown key IDs and oversized key sets", %{conn: conn, key: key, account: account} do
    assert conn |> exchange(sign(key, %{}, %{"kid" => "unknown"}), account) |> json_response(:unauthorized)
    %{"keys" => [public]} = JSON.decode!(jwks(key))

    stub(JWKSClient, :get, fn _, _ ->
      {:ok, %{status: 200, body: JSON.encode!(%{"keys" => List.duplicate(public, 21)})}}
    end)

    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
  end

  @tag timeout: 15_000
  test "enforces a total fetch deadline even when a transport never returns", %{conn: conn, key: key, account: account} do
    stub(JWKSClient, :get, fn _, _ -> Process.sleep(:infinity) end)
    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
  end

  test "hosted exchanges use the requester rate limiter before fetching keys", %{conn: conn, key: key, account: account} do
    stub(Environment, :tuist_hosted?, fn -> true end)
    parent = self()

    stub(RateLimit, :hit, fn rate_key, opts ->
      send(parent, {:rate_limited, rate_key, opts})
      {:deny, 300}
    end)

    assert_raise TooManyRequestsError, fn -> exchange(conn, sign(key), account) end
    assert_receive {:rate_limited, rate_key, opts}
    assert rate_key =~ "/api/auth/oidc/token"
    assert opts[:limit] == 300
    refute_receive {:jwks_fetch, _, _}
  end

  defp exchange(conn, token, account) do
    body = if is_nil(account), do: %{token: token}, else: %{token: token, account_handle: account}
    conn |> put_req_header("content-type", "application/json") |> post(~p"/api/auth/oidc/token", body)
  end

  defp sign(key, overrides \\ %{}, header \\ %{}) do
    claims =
      Map.merge(
        %{
          "iss" => @attrs.issuer,
          "sub" => "service:production",
          "aud" => "tuist",
          "exp" => DateTime.to_unix(DateTime.utc_now()) + 600
        },
        overrides
      )

    {_, token} =
      key |> JOSE.JWT.sign(Map.merge(%{"alg" => "RS256", "kid" => "workload-key"}, header), claims) |> JOSE.JWS.compact()

    token
  end

  defp jwks(key, overrides \\ %{}) do
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    JSON.encode!(%{"keys" => [Map.merge(Map.put(public, "kid", "workload-key"), overrides)]})
  end
end
