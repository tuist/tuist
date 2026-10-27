defmodule Tuist.Kura.SelfHostedClientsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kura.SelfHostedClient
  alias Tuist.Kura.SelfHostedClients
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  describe "create_self_hosted_client/2" do
    test "issues a credential and returns the plaintext secret once" do
      account = AccountsFixtures.organization_fixture().account

      assert {:ok, {%SelfHostedClient{} = client, secret}} =
               SelfHostedClients.create_self_hosted_client(account, %{name: "production"})

      assert client.account_id == account.id
      assert client.name == "production"
      assert String.starts_with?(client.client_id, "cache_")
      assert byte_size(secret) > 0
      refute client.encrypted_secret_hash == secret
      assert client.secret_last_four == String.slice(secret, -4, 4)
    end

    test "rejects a blank name" do
      account = AccountsFixtures.organization_fixture().account

      assert {:error, changeset} =
               SelfHostedClients.create_self_hosted_client(account, %{name: ""})

      refute changeset.valid?
    end

    test "rejects a duplicate name for the same account" do
      account = AccountsFixtures.organization_fixture().account
      {:ok, _} = SelfHostedClients.create_self_hosted_client(account, %{name: "mesh"})

      assert {:error, changeset} =
               SelfHostedClients.create_self_hosted_client(account, %{name: "mesh"})

      refute changeset.valid?
    end
  end

  describe "verify/2" do
    test "returns the owning account for a valid, entitled credential" do
      # A non-hosted (self-managed) deployment grants every entitlement.
      stub(Environment, :tuist_hosted?, fn -> false end)
      account = AccountsFixtures.organization_fixture().account
      {:ok, {client, secret}} = SelfHostedClients.create_self_hosted_client(account, %{name: "a"})

      assert {:ok, verified_account} = SelfHostedClients.verify(client.client_id, secret)
      assert verified_account.id == account.id
    end

    test "rejects a valid credential whose account is not entitled to self-hosting" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      {:ok, {client, secret}} = SelfHostedClients.create_self_hosted_client(account, %{name: "a"})

      assert SelfHostedClients.verify(client.client_id, secret) == :error
    end

    test "accepts a valid credential whose account is on the enterprise plan" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, {client, secret}} = SelfHostedClients.create_self_hosted_client(account, %{name: "a"})

      assert {:ok, verified_account} = SelfHostedClients.verify(client.client_id, secret)
      assert verified_account.id == account.id
    end

    test "rejects a wrong secret" do
      account = AccountsFixtures.organization_fixture().account
      {:ok, {client, _secret}} = SelfHostedClients.create_self_hosted_client(account, %{name: "a"})

      assert SelfHostedClients.verify(client.client_id, "wrong-secret") == :error
    end

    test "rejects an unknown client_id" do
      assert SelfHostedClients.verify("kura_does-not-exist", "whatever") == :error
    end

    test "rejects non-binary input" do
      assert SelfHostedClients.verify(nil, nil) == :error
    end
  end

  describe "list_self_hosted_clients/1 and revoke_self_hosted_client/1" do
    test "lists only the account's credentials and revokes them" do
      account = AccountsFixtures.organization_fixture().account
      other_account = AccountsFixtures.organization_fixture().account
      {:ok, {client, _}} = SelfHostedClients.create_self_hosted_client(account, %{name: "a"})
      {:ok, _} = SelfHostedClients.create_self_hosted_client(other_account, %{name: "b"})

      assert [listed] = SelfHostedClients.list_self_hosted_clients(account)
      assert listed.id == client.id

      assert {:ok, _} = SelfHostedClients.revoke_self_hosted_client(client)
      assert SelfHostedClients.list_self_hosted_clients(account) == []
    end
  end
end
