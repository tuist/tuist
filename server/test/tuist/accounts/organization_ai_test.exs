defmodule Tuist.Accounts.OrganizationAITest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.OrganizationAI
  alias Tuist.Accounts.OrganizationAIConnection
  alias Tuist.FeatureFlags
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    stub(FeatureFlags, :organization_ai_enabled?, fn _ -> true end)
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
    member = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(member, org)

    operations = fn actor ->
      [
        fn -> OrganizationAI.settings(actor, account) end,
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

    stub(FeatureFlags, :organization_ai_enabled?, fn actor ->
      assert actor.id == account.id
      false
    end)

    for operation <- operations.(user), do: assert(operation.() == {:error, :disabled})
    reject(PinnedHTTP, :request, 3)
    assert {:error, :disabled} = OrganizationAI.complete(account, [])
    assert Repo.get!(OrganizationAIConnection, connection.id)
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
