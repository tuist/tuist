defmodule Tuist.WebhooksTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_endpoint/2" do
    test "persists the endpoint and returns the plaintext signing secret" do
      account = AccountsFixtures.user_fixture().account

      assert {:ok, endpoint, secret} =
               Webhooks.create_endpoint(account.id, %{"name" => "Jira ingest", "url" => "https://example.com/hook"})

      assert endpoint.account_id == account.id
      assert endpoint.name == "Jira ingest"
      assert endpoint.url == "https://example.com/hook"
      assert String.starts_with?(secret, "whsec_")
      # Cloak decrypts the column transparently on read.
      assert endpoint.signing_secret == secret
    end

    test "rejects non-HTTPS URLs" do
      account = AccountsFixtures.user_fixture().account

      assert {:error, %Ecto.Changeset{} = changeset} =
               Webhooks.create_endpoint(account.id, %{"name" => "Bad", "url" => "http://example.com/hook"})

      assert "must be a valid HTTPS URL" in errors_on(changeset).url
    end

    test "rejects a blank name" do
      account = AccountsFixtures.user_fixture().account

      assert {:error, %Ecto.Changeset{} = changeset} =
               Webhooks.create_endpoint(account.id, %{"name" => "", "url" => "https://example.com/hook"})

      assert errors_on(changeset).name != []
    end
  end

  describe "list_endpoints/1 + get_account_endpoint/2" do
    test "scopes to the requesting account" do
      a = AccountsFixtures.user_fixture().account
      b = AccountsFixtures.user_fixture().account
      {:ok, a_endpoint, _} = Webhooks.create_endpoint(a.id, %{"name" => "A", "url" => "https://a.example/h"})
      {:ok, _b_endpoint, _} = Webhooks.create_endpoint(b.id, %{"name" => "B", "url" => "https://b.example/h"})

      assert [endpoint] = Webhooks.list_endpoints(a.id)
      assert endpoint.id == a_endpoint.id

      assert {:ok, _} = Webhooks.get_account_endpoint(a_endpoint.id, a.id)
      assert {:error, :not_found} = Webhooks.get_account_endpoint(a_endpoint.id, b.id)
    end
  end

  describe "rotate_signing_secret/1" do
    test "replaces the secret in place and returns the new plaintext" do
      account = AccountsFixtures.user_fixture().account

      {:ok, endpoint, original} =
        Webhooks.create_endpoint(account.id, %{"name" => "Hook", "url" => "https://example.com/hook"})

      assert {:ok, rotated, new_plaintext} = Webhooks.rotate_signing_secret(endpoint)
      assert rotated.id == endpoint.id
      assert new_plaintext != original
      assert rotated.signing_secret == new_plaintext
    end
  end

  describe "delete_endpoint/1" do
    test "removes the endpoint" do
      account = AccountsFixtures.user_fixture().account
      {:ok, endpoint, _} = Webhooks.create_endpoint(account.id, %{"name" => "Hook", "url" => "https://example.com/hook"})

      assert {:ok, _} = Webhooks.delete_endpoint(endpoint)
      assert {:error, :not_found} = Webhooks.get_endpoint(endpoint.id)
    end
  end
end
