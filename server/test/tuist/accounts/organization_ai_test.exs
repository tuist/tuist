defmodule Tuist.Accounts.OrganizationAITest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.ClaudeLinkedBilling
  alias Tuist.Accounts.OrganizationAI
  alias Tuist.Accounts.OrganizationAIConnection
  alias Tuist.Accounts.OrganizationAITaskRoute
  alias Tuist.FeatureFlags
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
    %{user: user, organization: organization, account: organization.account}
  end

  test "connections own encrypted keys independently of models and the explicit default", %{user: user, account: account} do
    connection = connection(user, account, "https://api.fireworks.ai/inference/v1", "private-key")
    first = model(user, account, connection.id, "accounts/fireworks/models/first")
    second = model(user, account, connection.id, "accounts/fireworks/models/second")
    another_connection = connection(user, account, "https://api.fireworks.ai/inference/v1", "another-key")
    another_model = model(user, account, another_connection.id, first.model_id)

    assert {:ok, %{connections: connections, models: models, default_model_id: nil}} =
             OrganizationAI.settings(user, account)

    assert length(connections) == 2
    assert Enum.map(models, & &1.id) == [first.id, second.id, another_model.id]
    refute inspect(connections) =~ "private-key"
    raw = Repo.one!(from c in "organization_ai_connections", where: c.id == ^connection.id, select: c.api_key)
    refute raw =~ "private-key"
    refute inspect(Repo.get!(OrganizationAIConnection, connection.id)) =~ "private-key"

    reject(PinnedHTTP, :request, 3)
    assert {:error, :not_configured} = OrganizationAI.complete(account, [])
    assert {:ok, _} = OrganizationAI.set_default(user, account, second.id)
    assert {:ok, %{default_model_id: id}} = OrganizationAI.settings(user, account)
    assert id == second.id

    assert {:ok, _} =
             OrganizationAI.save_connection(user, account, %{
               "_id" => connection.id,
               "name" => "Renamed",
               "api_key" => " "
             })

    assert Repo.get!(OrganizationAIConnection, connection.id).api_key == "private-key"

    assert {:error, :invalid_configuration} =
             OrganizationAI.save_connection(user, account, %{
               "_id" => connection.id,
               "base_url" => "https://api.openai.com/v1",
               "api_key" => " "
             })

    assert Repo.get!(OrganizationAIConnection, connection.id).base_url == "https://api.fireworks.ai/inference/v1"

    assert {:ok, _} =
             OrganizationAI.save_connection(user, account, %{
               "_id" => connection.id,
               "base_url" => "https://api.openai.com/v1/",
               "api_key" => "private-key"
             })

    assert Repo.get!(OrganizationAIConnection, connection.id).base_url == "https://api.openai.com/v1"
    assert {:ok, %{models: [_, _, _], default_model_id: default_id}} = OrganizationAI.settings(user, account)
    assert default_id == second.id

    assert {:error, :invalid_configuration} =
             OrganizationAI.save_model(user, account, %{
               "connection_id" => connection.id,
               "name" => "Duplicate",
               "model_id" => first.model_id
             })
  end

  test "routing follows the selected model's connection and its rotated key", %{user: user, account: account} do
    messages = [%{role: "user", content: "Explain this build failure"}]
    body = %{"choices" => [%{"message" => %{"content" => "A missing dependency"}}]}

    for {provider, url, upstream_id} <- [
          {"openai", "https://api.openai.com/v1/chat/completions", "gpt-example"},
          {"fireworks", "https://api.fireworks.ai/inference/v1/chat/completions", "accounts/fireworks/models/example"},
          {"together", "https://api.together.ai/v1/chat/completions", "org/model:version"},
          {"custom", "https://1.1.1.1/company/v2/chat/completions", "custom/model"}
        ] do
      connection = connection(user, account, String.replace_suffix(url, "/chat/completions", ""), "#{provider}-key")
      unused = model(user, account, connection.id, "other-model")
      selected = model(user, account, connection.id, upstream_id)
      assert {:ok, _} = OrganizationAI.set_default(user, account, selected.id)

      pinned = URI.to_string(%{URI.parse(url) | host: "1.1.1.1"})

      stub(SSRFGuard, :pin, fn ^url -> {:ok, pinned, URI.parse(url).host} end)

      stub(PinnedHTTP, :request, fn "POST", ^pinned, opts ->
        assert opts[:headers] == [{"authorization", "Bearer #{provider}-key"}, {"content-type", "application/json"}]

        assert JSON.decode!(opts[:body]) == %{
                 "model" => upstream_id,
                 "messages" => [%{"role" => "user", "content" => "Explain this build failure"}],
                 "stream" => false
               }

        assert opts[:connect_options][:hostname] == URI.parse(url).host
        assert opts[:connect_options][:transport_opts][:verify] == :verify_peer
        assert opts[:accept_status] == 200
        assert opts[:max_body_bytes] == 4 * 1024 * 1024
        {:ok, %{status: 200, body: JSON.encode!(body)}}
      end)

      assert {:ok, ^body} = OrganizationAI.complete(account, messages)

      assert {:ok, _} =
               OrganizationAI.save_connection(user, account, %{"_id" => connection.id, "api_key" => "rotated-key"})

      assert {:ok, _} = OrganizationAI.set_default(user, account, unused.id)

      stub(PinnedHTTP, :request, fn "POST", ^pinned, opts ->
        assert {"authorization", "Bearer rotated-key"} in opts[:headers]
        assert JSON.decode!(opts[:body])["model"] == "other-model"
        {:error, {:unexpected_status, 401}}
      end)

      assert {:error, {:provider_error, 401}} = OrganizationAI.complete(account, messages)
    end
  end

  test "removal clears a dependent default without selecting a fallback", %{user: user, account: account} do
    first_connection = connection(user, account)
    second_connection = connection(user, account)
    first = model(user, account, first_connection.id)
    second = model(user, account, second_connection.id)
    assert {:ok, _} = OrganizationAI.set_default(user, account, first.id)
    assert {:ok, :ok} = OrganizationAI.remove_connection(user, account, first_connection.id)

    assert {:ok, %{connections: [remaining], models: [remaining_model], default_model_id: nil}} =
             OrganizationAI.settings(user, account)

    assert remaining.id == second_connection.id
    assert remaining_model.id == second.id
    reject(PinnedHTTP, :request, 3)
    assert {:error, :not_configured} = OrganizationAI.complete(account, [])
    assert {:ok, _} = OrganizationAI.set_default(user, account, second.id)
    assert {:ok, :ok} = OrganizationAI.remove_model(user, account, second.id)
    assert {:ok, %{connections: [_], models: [], default_model_id: nil}} = OrganizationAI.settings(user, account)
    replacement = model(user, account, second_connection.id)
    assert {:ok, _} = OrganizationAI.set_default(user, account, replacement.id)
    assert {:ok, nil} = OrganizationAI.set_default(user, account, "")
    assert {:error, :not_configured} = OrganizationAI.complete(account, [])
  end

  test "task routes override the default, fall back to it, and work without one", %{user: user, account: account} do
    connection = connection(user, account, "https://api.together.ai/v1")
    explainer = model(user, account, connection.id, "openai/gpt-oss-120b")
    classifier = model(user, account, connection.id, "together/Tev1-4B-experimental")
    stub(SSRFGuard, :pin, fn url -> {:ok, url, "api.together.ai"} end)

    stub(PinnedHTTP, :request, fn "POST", _, opts ->
      send(self(), {:model, JSON.decode!(opts[:body])["model"]})
      {:ok, %{status: 200, body: ~s({"choices":[]})}}
    end)

    routed_model = fn opts ->
      case OrganizationAI.complete(account, [], opts) do
        {:ok, _} ->
          assert_received {:model, model}
          model

        error ->
          error
      end
    end

    # Without a default, only a routed task sends requests.
    assert {:ok, route} =
             OrganizationAI.save_route(user, account, %{"task" => "pulse_grouping", "model_id" => classifier.id})

    assert route.task == :pulse_grouping
    assert routed_model.(task: :pulse_grouping) == "together/Tev1-4B-experimental"
    assert routed_model.(task: :pulse_explanation) == {:error, :not_configured}
    assert routed_model.([]) == {:error, :not_configured}

    assert {:ok, _} = OrganizationAI.set_default(user, account, explainer.id)
    assert routed_model.(task: :pulse_grouping) == "together/Tev1-4B-experimental"
    assert routed_model.(task: :pulse_explanation) == "openai/gpt-oss-120b"
    assert routed_model.([]) == "openai/gpt-oss-120b"
    assert OrganizationAI.complete(account, []) == OrganizationAI.complete(account, [], [])
    assert_received {:model, "openai/gpt-oss-120b"}
    assert_received {:model, "openai/gpt-oss-120b"}

    # Each task has one route; editing one cannot take another task's.
    assert {:error, :invalid_configuration} =
             OrganizationAI.save_route(user, account, %{"task" => "pulse_grouping", "model_id" => explainer.id})

    assert {:ok, explanation} =
             OrganizationAI.save_route(user, account, %{"task" => "pulse_explanation", "model_id" => classifier.id})

    assert {:error, :invalid_configuration} =
             OrganizationAI.save_route(user, account, %{"_id" => explanation.id, "task" => "pulse_grouping"})

    assert {:ok, _} = OrganizationAI.save_route(user, account, %{"_id" => explanation.id, "model_id" => explainer.id})
    assert routed_model.(task: :pulse_explanation) == "openai/gpt-oss-120b"

    for attrs <- [
          %{"task" => "unknown", "model_id" => explainer.id},
          %{"task" => "none", "model_id" => explainer.id},
          %{"task" => "pulse_explanation", "model_id" => "none"},
          %{"task" => "pulse_explanation", "model_id" => 999_999_999}
        ] do
      assert {:error, :invalid_configuration} = OrganizationAI.save_route(user, account, attrs)
    end

    assert {:ok, %{routes: routes}} = OrganizationAI.settings(user, account)

    assert Enum.map(routes, &{&1.task, &1.model_id}) == [
             {:pulse_grouping, classifier.id},
             {:pulse_explanation, explainer.id}
           ]

    # Removing a routed model removes its route, so the task uses the default again.
    assert {:ok, :ok} = OrganizationAI.remove_model(user, account, classifier.id)
    assert {:ok, %{routes: [%{task: :pulse_explanation}]}} = OrganizationAI.settings(user, account)
    assert routed_model.(task: :pulse_grouping) == "openai/gpt-oss-120b"

    # Removing the default leaves routed tasks working.
    assert {:ok, nil} = OrganizationAI.set_default(user, account, nil)
    assert routed_model.(task: :pulse_explanation) == "openai/gpt-oss-120b"
    assert routed_model.(task: :pulse_grouping) == {:error, :not_configured}

    assert {:ok, :ok} = OrganizationAI.remove_route(user, account, explanation.id)
    assert routed_model.(task: :pulse_explanation) == {:error, :not_configured}
    assert {:ok, %{routes: []}} = OrganizationAI.settings(user, account)

    # Removing a connection cascades through its models to their routes.
    assert {:ok, _} = OrganizationAI.save_route(user, account, %{"task" => "pulse_grouping", "model_id" => explainer.id})
    assert {:ok, :ok} = OrganizationAI.remove_connection(user, account, connection.id)
    assert {:ok, %{routes: []}} = OrganizationAI.settings(user, account)

    assert_raise ArgumentError, fn -> OrganizationAI.complete(account, [], task: :unknown) end
  end

  test "rejects cross-organization connections, models and defaults", %{user: user, account: account} do
    foreign_user = AccountsFixtures.user_fixture()
    foreign_account = AccountsFixtures.organization_fixture(creator: foreign_user).account
    foreign_connection = connection(foreign_user, foreign_account)
    foreign_model = model(foreign_user, foreign_account, foreign_connection.id)

    assert {:error, :not_found} =
             OrganizationAI.save_connection(user, account, %{"_id" => foreign_connection.id, "api_key" => "replacement"})

    assert {:error, :invalid_configuration} =
             OrganizationAI.save_model(user, account, %{
               "connection_id" => foreign_connection.id,
               "name" => "Foreign",
               "model_id" => "example"
             })

    assert {:error, :not_found} =
             OrganizationAI.save_model(user, account, %{"_id" => foreign_model.id, "name" => "Hijacked"})

    assert {:error, :not_found} = OrganizationAI.set_default(user, account, foreign_model.id)

    assert {:error, :invalid_configuration} =
             OrganizationAI.save_route(user, account, %{"task" => "pulse_grouping", "model_id" => foreign_model.id})

    assert {:ok, foreign_route} =
             OrganizationAI.save_route(foreign_user, foreign_account, %{
               "task" => "pulse_grouping",
               "model_id" => foreign_model.id
             })

    own_model = model(user, account, connection(user, account).id)

    assert {:error, :not_found} =
             OrganizationAI.save_route(user, account, %{"_id" => foreign_route.id, "model_id" => own_model.id})

    assert {:error, :not_found} = OrganizationAI.remove_route(user, account, foreign_route.id)
    assert {:ok, %{routes: [%{model_id: foreign_model_id}]}} = OrganizationAI.settings(foreign_user, foreign_account)
    assert foreign_model_id == foreign_model.id
    assert {:error, :not_found} = OrganizationAI.remove_connection(user, account, foreign_connection.id)
    assert {:error, :not_found} = OrganizationAI.remove_model(user, account, foreign_model.id)
    assert {:ok, %{connections: [connection], models: [model]}} = OrganizationAI.settings(foreign_user, foreign_account)
    assert connection.id == foreign_connection.id
    assert model.name != "Hijacked"
  end

  test "rechecks authorization and the account flag for every operation", %{
    user: user,
    account: account,
    organization: org
  } do
    connection = connection(user, account)
    model = model(user, account, connection.id)
    assert {:ok, route} = OrganizationAI.save_route(user, account, %{"task" => "pulse_grouping", "model_id" => model.id})
    member = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(member, org)

    operations = fn actor ->
      [
        fn -> OrganizationAI.settings(actor, account) end,
        fn -> OrganizationAI.save_route(actor, account, %{"task" => "pulse_explanation", "model_id" => model.id}) end,
        fn -> OrganizationAI.remove_route(actor, account, route.id) end,
        fn -> OrganizationAI.save_connection(actor, account, %{}) end,
        fn -> OrganizationAI.save_model(actor, account, %{}) end,
        fn -> OrganizationAI.set_default(actor, account, model.id) end,
        fn -> OrganizationAI.remove_model(actor, account, model.id) end,
        fn -> OrganizationAI.remove_connection(actor, account, connection.id) end
      ]
    end

    for actor <- [member, AccountsFixtures.user_fixture()],
        operation <- operations.(actor),
        do: assert(operation.() == {:error, :forbidden})

    assert {:ok, _} = Accounts.update_user_role_in_organization(user, org, :user)
    for operation <- operations.(user), do: assert(operation.() == {:error, :forbidden})

    stub(FeatureFlags, :organization_luft_enabled?, fn actor ->
      assert actor.id == account.id
      false
    end)

    for operation <- operations.(user), do: assert(operation.() == {:error, :disabled})
    reject(PinnedHTTP, :request, 3)
    assert {:error, :disabled} = OrganizationAI.complete(account, [])
    assert {:error, :disabled} = OrganizationAI.complete(account, [], task: :pulse_grouping)
    assert Repo.get!(OrganizationAIConnection, connection.id)
    assert Repo.get!(OrganizationAITaskRoute, route.id).task == :pulse_grouping
  end

  test "rejects malformed settings and personal accounts", %{user: user, account: account} do
    for attrs <- [
          %{},
          %{"name" => "Name", "base_url" => "unknown", "api_key" => "key"},
          %{"name" => "Name", "base_url" => "https://api.openai.com/v1", "api_key" => "bad\r\nheader"}
        ] do
      assert {:error, :invalid_configuration} = OrganizationAI.save_connection(user, account, attrs)
    end

    connection = connection(user, account)

    for model_id <- ["", "  ", nil, "../model?key=x"] do
      assert {:error, :invalid_configuration} =
               OrganizationAI.save_model(user, account, %{
                 "connection_id" => connection.id,
                 "name" => "Name",
                 "model_id" => model_id
               })
    end

    for id <- ["not-an-id", "999999999999999999999999999999999999999"] do
      assert {:error, :not_found} = OrganizationAI.set_default(user, account, id)
    end

    personal = AccountsFixtures.user_fixture(preload: [:account])
    assert {:error, :forbidden} = OrganizationAI.save_connection(personal, personal.account, %{})
    assert {:error, :not_configured} = OrganizationAI.complete(personal.account, [])
  end

  test "rejects unsafe endpoints and rechecks DNS before sending a credential", %{user: user, account: account} do
    for url <- [
          "http://1.1.1.1/v1",
          "https://127.0.0.1/v1",
          "https://169.254.169.254/v1",
          "https://[::1]/v1",
          "https://10.0.0.1/v1",
          "https://localhost/v1",
          "https://user:password@api.openai.com/v1",
          "https://api.openai.com/v1?token=x",
          "https://api.openai.com/v1#fragment",
          "https://api.openai.com:0/v1"
        ] do
      assert {:error, :invalid_configuration} =
               OrganizationAI.save_connection(user, account, %{
                 "name" => "Unsafe",
                 "base_url" => url,
                 "api_key" => "secret"
               })
    end

    connection = connection(user, account)
    selected = model(user, account, connection.id)
    assert {:ok, _} = OrganizationAI.set_default(user, account, selected.id)
    stub(SSRFGuard, :pin, fn _ -> {:error, :private_ip_resolved} end)
    reject(PinnedHTTP, :request, 3)
    assert {:error, :provider_unavailable} = OrganizationAI.complete(account, [])
  end

  test "sanitizes transport and invalid response errors without fallback", %{user: user, account: account} do
    connection = connection(user, account)
    selected = model(user, account, connection.id)
    assert {:ok, _} = OrganizationAI.set_default(user, account, selected.id)
    stub(SSRFGuard, :pin, fn _ -> {:ok, "https://1.1.1.1/v1/chat/completions", "api.openai.com"} end)

    for {response, expected} <- [
          {{:error, {:unexpected_status, 302}}, {:error, {:provider_error, 302}}},
          {{:error, :response_too_large}, {:error, :provider_unavailable}},
          {{:error, {:timeout, "private-key"}}, {:error, :provider_unavailable}},
          {{:ok, %{status: 200, body: "private-key"}}, {:error, :provider_unavailable}},
          {{:ok, %{status: 200, body: ~s({"choices":"invalid"})}}, {:error, :provider_unavailable}}
        ] do
      expect(PinnedHTTP, :request, fn _, _, _ -> response end)
      result = OrganizationAI.complete(account, [])
      assert result == expected
      refute inspect(result) =~ "private-key"
    end
  end

  describe "Claude linked billing" do
    setup do
      stub(Tuist.Environment, :anthropic_linked_billing_config, fn ->
        %{
          client_id: "client-123",
          client_assertion_audience: "aud-from-console",
          organization_id: "org-tuist",
          workspace_id: "wrkspc-1",
          service_account_id: "svac-1",
          federation_rule_id: "fdrl-1"
        }
      end)

      stub(Tuist.KeyValueStore, :get, fn _key, _opts -> nil end)
      stub(Tuist.KeyValueStore, :put, fn _key, _value, _opts -> :ok end)
      :ok
    end

    test "links once per organization, bills the linked profile and unlinks on removal", %{
      user: user,
      account: account
    } do
      jwks = ClaudeLinkedBilling.jwks()

      verify = fn assertion, audience ->
        [key] = jwks["keys"]
        assert {true, %JOSE.JWT{fields: claims}, _} = JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["ES256"], assertion)
        assert claims["iss"] == ClaudeLinkedBilling.issuer()
        assert claims["aud"] == audience
      end

      stub(Req, :post, fn
        "https://api.anthropic.com/v1/oauth/token", opts ->
          verify.(opts[:json].assertion, "https://api.anthropic.com")
          assert opts[:json].service_account_id == "svac-1"
          {:ok, %Req.Response{status: 200, body: %{"access_token" => "sk-ant-oat01-operator", "expires_in" => 600}}}

        "https://api.anthropic.com/v1/user_profiles", opts ->
          assert {"authorization", "Bearer sk-ant-oat01-operator"} in opts[:headers]
          {:ok, %Req.Response{status: 201, body: %{"id" => "uprof_#{System.unique_integer([:positive])}"}}}

        "https://auth.claude.com/v1/oauth/par", opts ->
          verify.(opts[:json].client_assertion, "aud-from-console")
          send(self(), {:par, opts[:json]})
          {:ok, %Req.Response{status: 201, body: %{"request_uri" => "urn:request:1", "expires_in" => 600}}}

        "https://auth.claude.com/v1/oauth/token", opts ->
          assert %{grant_type: "authorization_code", code: "the-code", code_verifier: "verifier"} = opts[:json]
          {:ok, %Req.Response{status: 200, body: %{"connection_id" => "ocon_1", "access_token" => "unused"}}}

        "https://auth.claude.com/v1/oauth/revoke", opts ->
          send(self(), {:revoked, opts[:json].user_profile_id})
          {:ok, %Req.Response{status: 200, body: %{"revoked_connection_ids" => ["ocon_1"]}}}
      end)

      assert {:ok, %{url: url, state: state, code_verifier: verifier}} = OrganizationAI.start_claude_link(user, account)
      assert url == "https://auth.claude.com/oauth/authorize?client_id=client-123&request_uri=urn%3Arequest%3A1"
      assert_received {:par, par}
      profile_id = par.user_profile_id
      assert par.state == state
      assert par.code_challenge == Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

      assert %{scope: "billing:attribution", connection_type: "organization_shared", connection_auth_target: "platform"} =
               par

      # A second attempt reuses the organization's profile instead of creating another.
      assert {:ok, _} = OrganizationAI.start_claude_link(user, account)
      assert_received {:par, %{user_profile_id: ^profile_id}}

      assert {:ok, linked} = OrganizationAI.link_claude(user, account, "the-code", "verifier")
      # Linking again replaces the stored connection rather than adding a provider.
      assert {:ok, relinked} = OrganizationAI.link_claude(user, account, "the-code", "verifier")
      assert relinked.id == linked.id

      assert {:ok, %{connections: [%{kind: "claude_linked_billing", base_url: nil}]}} =
               OrganizationAI.settings(user, account)

      # Linked connections are never edited as keys.
      assert {:error, :not_found} =
               OrganizationAI.save_connection(user, account, %{
                 "_id" => linked.id,
                 "base_url" => "https://1.1.1.1/v1",
                 "api_key" => "x"
               })

      selected = model(user, account, linked.id, "claude-sonnet-5-5")
      assert {:ok, _} = OrganizationAI.set_default(user, account, selected.id)

      url = "https://api.anthropic.com/v1/chat/completions"
      stub(SSRFGuard, :pin, fn ^url -> {:ok, "https://1.1.1.1/v1/chat/completions", "api.anthropic.com"} end)

      expect(PinnedHTTP, :request, fn "POST", _url, opts ->
        assert {"authorization", "Bearer sk-ant-oat01-operator"} in opts[:headers]
        assert {"anthropic-beta", "user-profiles-billing-2026-10-01"} in opts[:headers]
        assert {"anthropic-user-profile-id", profile_id} in opts[:headers]

        assert JSON.decode!(opts[:body]) == %{
                 "model" => "claude-sonnet-5-5",
                 "messages" => [],
                 "stream" => false,
                 "billing_policy" => %{"type" => "billing_policy", "bill_to" => "user_profile"}
               }

        {:ok, %{status: 200, body: ~s({"choices":[]})}}
      end)

      assert {:ok, %{"choices" => []}} = OrganizationAI.complete(account, [])

      assert {:ok, :ok} = OrganizationAI.remove_connection(user, account, linked.id)
      assert_received {:revoked, ^profile_id}
      assert {:ok, %{connections: [], models: [], default_model_id: nil}} = OrganizationAI.settings(user, account)
    end

    test "keeps the link when Anthropic can't unlink it, and is unavailable until configured", %{
      user: user,
      account: account
    } do
      Repo.update_all(from(o in Tuist.Accounts.Organization, where: o.id == ^account.organization_id),
        set: [anthropic_user_profile_id: "uprof_existing"]
      )

      stub(Req, :post, fn "https://auth.claude.com/v1/oauth/token", _ ->
        {:ok, %Req.Response{status: 200, body: %{"connection_id" => "ocon_2"}}}
      end)

      assert {:ok, linked} = OrganizationAI.link_claude(user, account, "code", "verifier")

      stub(Req, :post, fn "https://auth.claude.com/v1/oauth/revoke", _ -> {:ok, %Req.Response{status: 503, body: %{}}} end)

      assert {:error, :unlink_failed} = OrganizationAI.remove_connection(user, account, linked.id)
      assert Repo.get!(OrganizationAIConnection, linked.id)

      stub(Tuist.Environment, :anthropic_linked_billing_config, fn -> %{client_id: nil} end)
      reject(Req, :post, 2)
      assert {:error, :not_configured} = OrganizationAI.start_claude_link(user, account)
    end
  end

  defp connection(user, account, base_url \\ "https://api.openai.com/v1", key \\ "private-key") do
    assert {:ok, connection} =
             OrganizationAI.save_connection(user, account, %{
               "name" => "Inference provider",
               "base_url" => base_url,
               "api_key" => key
             })

    connection
  end

  defp model(user, account, connection_id, model_id \\ "example") do
    assert {:ok, model} =
             OrganizationAI.save_model(user, account, %{
               "connection_id" => connection_id,
               "name" => "Model #{model_id}",
               "model_id" => model_id
             })

    model
  end
end
