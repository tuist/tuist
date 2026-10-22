defmodule TuistWeb.API.OIDCWorkloadControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.Authorization
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

  # Seed directly so verification bounds also cover rows beyond creation limits.
  defp create_policy(project, attrs) do
    attrs = Map.update!(attrs, :name, &"#{&1} #{project.id}")

    %OIDCTrustPolicy{account_id: project.account_id}
    |> OIDCTrustPolicy.changeset(attrs)
    |> Repo.insert()
  end

  setup_all do
    %{key: JOSE.JWK.generate_key({:rsa, 2048}), other_key: JOSE.JWK.generate_key({:rsa, 2048})}
  end

  setup %{key: key} do
    project = ProjectsFixtures.project_fixture(preload: [:account])
    {:ok, policy} = create_policy(project, @attrs)
    stub(KeyValueStore, :get_or_update, fn _, _, fetch -> fetch.() end)
    stub(SSRFGuard, :pin, fn url -> {:ok, url, "keys.example"} end)
    parent = self()

    stub(JWKSClient, :get, fn url, opts ->
      send(parent, {:jwks_fetch, url, opts})
      {:ok, %{status: 200, body: jwks(key)}}
    end)

    %{project: project, account: project.account.name, policy: policy}
  end

  test "issues one-hour CI access to all projects in the selected account", %{
    conn: conn,
    key: key,
    project: project,
    account: account
  } do
    second = ProjectsFixtures.project_fixture(account: project.account)
    {:ok, _} = create_policy(second, @attrs)
    ProjectsFixtures.project_fixture(account: project.account, vcs_connection: [repository_full_handle: "tuist/tuist"])
    response = conn |> exchange(sign(key), String.upcase(account)) |> json_response(:ok)
    assert response["expires_in"] == 3600
    refute Map.has_key?(response, "refresh_token")
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["exp"] - claims["iat"] == 3600
    assert claims["all_projects"] == true
    refute Map.has_key?(claims, "project_ids")
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

  test "issued CI credentials include future projects and follow current account ownership", %{
    conn: conn,
    key: key,
    project: project,
    account: account
  } do
    existing = ProjectsFixtures.project_fixture(account: project.account)
    foreign = ProjectsFixtures.project_fixture(visibility: :private)
    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert {:ok, subject} = Guardian.resource_from_claims(claims)
    assert Authorization.authorize(:project_cache_read, subject, existing) == :ok
    refute Authorization.authorize(:project_cache_read, subject, foreign) == :ok
    refute Authorization.authorize(:account_update, subject, project.account) == :ok

    future = ProjectsFixtures.project_fixture(account: project.account)
    assert Authorization.authorize(:project_cache_read, subject, future) == :ok
    transferred_out = Repo.update!(Ecto.Changeset.change(project, account_id: foreign.account_id))
    transferred_in = Repo.update!(Ecto.Changeset.change(foreign, account_id: project.account_id))
    refute Authorization.authorize(:project_cache_read, subject, transferred_out) == :ok
    assert Authorization.authorize(:project_cache_read, subject, transferred_in) == :ok
    accessible = Projects.list_accessible_projects(subject, preload: [])
    assert MapSet.new(accessible, & &1.id) == MapSet.new([existing.id, future.id, transferred_in.id])
  end

  test "account-wide workload credentials cannot administer projects, runners or account members", %{
    conn: conn,
    key: key,
    project: project,
    account: account
  } do
    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert {:ok, subject} = Guardian.resource_from_claims(claims)
    assert claims["all_projects"] == true
    assert Authorization.authorize(:project_cache_update, subject, project) == :ok
    assert Authorization.authorize(:run_create, subject, project) == :ok

    for {action, resource} <- [
          project_create: project.account,
          project_update: project,
          project_delete: project,
          runners_read: project.account,
          runners_update: project.account,
          runners_interactive_access: project.account,
          account_update: project.account,
          account_delete: project.account,
          account_token_create: project.account,
          organization_read: project.account,
          invitation_create: project.account,
          member_update: project.account,
          member_delete: project.account
        ] do
      assert Authorization.authorize(action, subject, resource) == {:error, :forbidden},
             "workload credential must not authorize #{action}"
    end
  end

  for {provider, issuer, jwks_url, repository_claims} <- [
        {"GitHub Actions", "https://token.actions.githubusercontent.com",
         "https://token.actions.githubusercontent.com/.well-known/jwks", %{"repository" => "tuist/oidc-security"}},
        {"GitHub Enterprise", "https://token.actions.githubusercontent.com/tuist-enterprise",
         "https://token.actions.githubusercontent.com/.well-known/jwks", %{"repository" => "tuist/oidc-security"}},
        {"CircleCI", "https://oidc.circleci.com/org/tuist-org",
         "https://oidc.circleci.com/org/tuist-org/.well-known/jwks-pub.json",
         %{"oidc.circleci.com/vcs-origin" => "github.com/tuist/oidc-security"}},
        {"Bitrise", "https://token.builds.bitrise.io", "https://token.builds.bitrise.io/.well-known/jwks",
         %{
           "repository_owner" => "tuist",
           "repository_slug" => "oidc-security",
           "repository_url" => "https://github.com/tuist/oidc-security"
         }}
      ] do
    test "#{provider} stays repository-scoped even with a directly inserted reserved-issuer policy", %{
      conn: conn,
      key: key,
      other_key: other_key,
      project: unrelated,
      policy: policy,
      account: account
    } do
      issuer = unquote(issuer)
      jwks_url = unquote(jwks_url)
      repository_claims = unquote(Macro.escape(repository_claims))

      # Bypass changeset validation to prove issuer routing is also enforced at runtime.
      Repo.update!(Ecto.Changeset.change(policy, issuer: issuer))

      assert OIDCTrustPolicy.matches?(
               Repo.reload!(policy),
               Map.merge(repository_claims, %{
                 "iss" => issuer,
                 "aud" => "tuist",
                 "sub" => "service:production"
               })
             )

      linked =
        ProjectsFixtures.project_fixture(
          account: unrelated.account,
          vcs_connection: [repository_full_handle: "tuist/oidc-security"]
        )

      sibling =
        ProjectsFixtures.project_fixture(
          account: unrelated.account,
          vcs_connection: [repository_full_handle: "tuist/oidc-security"]
        )

      reject(&Accounts.oidc_trust_candidates/3)
      reject(&JWKSClient.get/2)
      parent = self()

      stub(Req, :get, fn url, _opts ->
        send(parent, {:builtin_jwks_fetch, url})
        {:ok, %{status: 200, body: JSON.decode!(jwks(key))}}
      end)

      overrides = Map.put(repository_claims, "iss", issuer)

      for account_handle <- [account, nil] do
        response = conn |> exchange(sign(key, overrides), account_handle) |> json_response(:ok)
        assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
        assert claims["scopes"] == ["ci"]
        assert claims["sub"] == to_string(unrelated.account_id)
        assert MapSet.new(claims["project_ids"]) == MapSet.new([linked.id, sibling.id])
        refute claims["all_projects"]
        assert {:ok, subject} = Guardian.resource_from_claims(claims)
        assert Authorization.authorize(:project_cache_read, subject, linked) == :ok
        assert Authorization.authorize(:project_cache_read, subject, unrelated) == {:error, :forbidden}
        future = ProjectsFixtures.project_fixture(account: unrelated.account)
        assert Authorization.authorize(:project_cache_read, subject, future) == {:error, :forbidden}
        assert_receive {:builtin_jwks_fetch, ^jwks_url}
      end

      # The matching policy's key must never rescue a forged built-in-provider token.
      assert conn |> exchange(sign(other_key, overrides), account) |> json_response(:unauthorized)
      refute_receive {:jwks_fetch, _, _}
    end
  end

  test "reserved unsupported issuers never fall back to directly inserted workload policies", %{
    conn: conn,
    key: key,
    policy: policy,
    account: account
  } do
    issuer = "https://token.actions.githubusercontent.com/enterprise/extra"
    Repo.update!(Ecto.Changeset.change(policy, issuer: issuer))
    reject(&Accounts.oidc_trust_candidates/3)
    reject(&JWKSClient.get/2)
    reject(&Req.get/2)

    assert conn |> exchange(sign(key, %{"iss" => issuer}), account) |> json_response(:bad_request)
    refute_receive {:jwks_fetch, _, _}
  end

  test "an account can exchange before it has any projects", %{conn: conn, key: key, project: project, account: account} do
    Repo.delete!(project)
    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["all_projects"] == true
    assert claims["sub"] == to_string(project.account_id)
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
    {:ok, _} = Accounts.delete_oidc_trust_policy(project.account, policy.id)
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
    {:ok, _} = create_policy(foreign, %{@attrs | jwks_url: "https://attacker.example/keys"})
    parent = self()

    stub(JWKSClient, :get, fn url, _ ->
      send(parent, {:key_url, url})
      {:ok, %{status: 200, body: jwks(if(url == @attrs.jwks_url, do: key, else: other))}}
    end)

    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["all_projects"] == true
    assert claims["sub"] == to_string(project.account_id)
    expected_url = @attrs.jwks_url
    assert_receive {:key_url, ^expected_url}
    refute_receive {:key_url, "https://attacker.example/keys"}
    assert conn |> exchange(sign(other), account) |> json_response(:unauthorized)
  end

  test "verification evidence includes only policies verified by their own key URL", %{
    conn: conn,
    key: key,
    other_key: other,
    account: account,
    project: project,
    policy: policy
  } do
    sibling = ProjectsFixtures.project_fixture(account: project.account)
    {:ok, _} = create_policy(sibling, %{@attrs | jwks_url: "https://other.example/keys"})

    stub(JWKSClient, :get, fn url, _ ->
      {:ok, %{status: 200, body: jwks(if(url == @attrs.jwks_url, do: key, else: other))}}
    end)

    assert {:ok, identity} = OIDC.claims(sign(key), account)
    assert Enum.map(identity.grants, & &1.policy_id) == [policy.id]
    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["all_projects"] == true
    assert claims["sub"] == to_string(project.account_id)
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

  test "unmatched or malformed audiences are rejected before fetching keys", %{conn: conn, key: key, account: account} do
    for audience <- ["other", nil, ["other"], ["tuist", 123], %{"aud" => "tuist"}] do
      assert conn |> exchange(sign(key, %{"aud" => audience}), account) |> json_response(:unauthorized)
    end

    refute_receive {:jwks_fetch, _, _}
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
      create_policy(project, %{
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
      create_policy(project, %{@attrs | name: "Typed", claims: %{"id" => 123, "protected" => true}})

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
    assert {:error, :invalid_signature} = Accounts.oidc_account_by_grants(identity)
    {:ok, _} = Accounts.delete_oidc_trust_policy(project.account, policy.id)
    assert {:error, :invalid_signature} = Accounts.oidc_account_by_grants(identity)
  end

  test "deleting a policy during key verification prevents account-wide token issuance", %{
    conn: conn,
    key: key,
    account: account,
    policy: policy
  } do
    stub(JWKSClient, :get, fn _, _ ->
      Repo.delete!(policy)
      {:ok, %{status: 200, body: jwks(key)}}
    end)

    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
  end

  for {field, value} <- [
        jwks_url: "https://changed.example/keys",
        issuer: "https://changed.example",
        audience: "changed",
        claims: %{"sub" => "changed"}
      ] do
    test "changing #{field} during verification prevents account-wide token issuance", %{
      conn: conn,
      key: key,
      account: account,
      policy: policy
    } do
      stub(JWKSClient, :get, fn _, _ ->
        Repo.update!(Ecto.Changeset.change(policy, %{unquote(field) => unquote(Macro.escape(value))}))
        {:ok, %{status: 200, body: jwks(key)}}
      end)

      assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    end
  end

  test "unrelated audiences cannot exhaust the JWKS URL budget", %{
    conn: conn,
    key: key,
    account: account,
    project: project
  } do
    for i <- 1..2 do
      {:ok, _} =
        create_policy(project, %{
          @attrs
          | name: "Other audience #{i}",
            audience: "other-#{i}",
            jwks_url: "https://other#{i}.example/jwks"
        })
    end

    response = conn |> exchange(sign(key), account) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["all_projects"] == true
    assert claims["sub"] == to_string(project.account_id)
    expected_url = @attrs.jwks_url
    assert_receive {:jwks_fetch, ^expected_url, _}
    refute_receive {:jwks_fetch, _, _}
  end

  test "unrelated audiences cannot exhaust the matching policy budget", %{
    conn: conn,
    key: key,
    account: account,
    project: project
  } do
    for i <- 1..19 do
      {:ok, _} = create_policy(project, %{@attrs | name: "Other #{i}", audience: "other"})
    end

    sibling = ProjectsFixtures.project_fixture(account: project.account)
    {:ok, _} = create_policy(sibling, %{@attrs | audience: "other"})
    response = conn |> exchange(sign(key, %{"aud" => ["tuist", "another"]}), account) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["all_projects"] == true
    assert claims["sub"] == to_string(project.account_id)
    expected_url = @attrs.jwks_url
    assert_receive {:jwks_fetch, ^expected_url, _}
    refute_receive {:jwks_fetch, _, _}
  end

  test "bounds distinct JWKS URLs before any fetch", %{conn: conn, key: key, account: account, project: project} do
    for i <- 1..2 do
      {:ok, _} =
        create_policy(project, %{
          @attrs
          | name: "Policy #{i}",
            jwks_url: "https://keys#{i}.example/jwks"
        })
    end

    assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
    refute_receive {:jwks_fetch, _, _}
  end

  test "bounds matching account policies before any fetch", %{
    conn: conn,
    key: key,
    account: account,
    project: project
  } do
    for i <- 1..19 do
      {:ok, _} = create_policy(project, %{@attrs | name: "Policy #{i}"})
    end

    sibling = ProjectsFixtures.project_fixture(account: project.account)
    {:ok, _} = create_policy(sibling, @attrs)
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
    {:ok, _} = Accounts.delete_oidc_trust_policy(project.account, policy.id)
    assert conn |> exchange(token, account) |> json_response(:unauthorized)
    refute_receive :successful_fetch
  end

  test "caches only bounded, key-type-specific public fields", %{
    conn: conn,
    key: key,
    account: account,
    project: project,
    policy: policy
  } do
    policy = Repo.update!(Ecto.Changeset.change(policy, jwks_url: "https://keys.example/normalized/#{project.id}"))

    stub(KeyValueStore, :get_or_update, fn cache_key, opts, fetch ->
      Mimic.call_original(KeyValueStore, :get_or_update, [cache_key, opts, fetch])
    end)

    keys = [
      {key, ~w(n e), %{"x" => String.duplicate("b", 10_000), "crv" => String.duplicate("c", 10_000)}},
      {JOSE.JWK.generate_key({:ec, "P-256"}), ~w(crv x y), %{"n" => "unused", "e" => "unused"}},
      {JOSE.JWK.generate_key({:okp, :Ed25519}), ~w(crv x), %{"y" => "unused", "n" => "unused"}}
    ]

    {padded, normalized} =
      keys
      |> Enum.map(fn {key, fields, extra} ->
        %{"keys" => [public]} = JSON.decode!(jwks(key))
        padded = Map.merge(public, Map.merge(extra, %{"padding" => String.duplicate("a", 10_000), "d" => "private"}))
        {padded, Map.take(public, ~w(kty kid alg) ++ fields)}
      end)
      |> Enum.unzip()

    stub(JWKSClient, :get, fn _, _ -> {:ok, %{status: 200, body: JSON.encode!(%{"keys" => padded})}} end)

    assert conn |> exchange(sign(key), account) |> json_response(:ok)
    cache_key = ["oidc", "workload-jwks", policy.jwks_url]
    assert KeyValueStore.get(cache_key, cache: :oidc_jwks) == %{"keys" => normalized}
    assert KeyValueStore.get(cache_key) == nil
  end

  test "rejects unbounded or malformed key identifiers before caching", %{conn: conn, key: key, account: account} do
    parent = self()

    stub(KeyValueStore, :get_or_update, fn _, _, fetch ->
      value = fetch.()
      send(parent, {:cache_fill, value})
      value
    end)

    for kid <- [String.duplicate("a", 257), %{"padded" => "identifier"}, 123, nil] do
      stub(JWKSClient, :get, fn _, _ -> {:ok, %{status: 200, body: jwks(key, %{"kid" => kid})}} end)
      assert conn |> exchange(sign(key), account) |> json_response(:unauthorized)
      assert_receive {:cache_fill, nil}
    end
  end

  test "accepts key identifiers at the byte limit", %{conn: conn, key: key, account: account} do
    kid = String.duplicate("a", 256)
    stub(JWKSClient, :get, fn _, _ -> {:ok, %{status: 200, body: jwks(key, %{"kid" => kid})}} end)
    assert conn |> exchange(sign(key, %{}, %{"kid" => kid}), account) |> json_response(:ok)
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
