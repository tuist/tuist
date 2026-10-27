defmodule Tuist.WebhooksTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp valid_attrs(extras \\ %{}) do
    Map.merge(
      %{"name" => "Hook", "url" => "https://example.com/hook", "event_types" => ["test_case.updated"]},
      extras
    )
  end

  describe "create_endpoint/2" do
    test "persists the endpoint and returns the plaintext signing secret" do
      account = AccountsFixtures.user_fixture().account

      assert {:ok, endpoint, secret} = Webhooks.create_endpoint(account.id, valid_attrs(%{"name" => "Jira ingest"}))

      assert endpoint.account_id == account.id
      assert endpoint.name == "Jira ingest"
      assert endpoint.url == "https://example.com/hook"
      assert endpoint.event_types == ["test_case.updated"]
      assert String.starts_with?(secret, "tuist_webhook_")
      # Scrubbed from the returned struct so callers don't accidentally
      # park the plaintext key in LiveView assigns.
      assert endpoint.signing_secret == nil
      # The worker-path load (`get_endpoint/1`) decrypts and returns the
      # full struct, proving the persisted value matches what was returned.
      assert {:ok, full} = Webhooks.get_endpoint(endpoint.id)
      assert full.signing_secret == secret
    end

    test "rejects non-HTTPS URLs" do
      account = AccountsFixtures.user_fixture().account

      assert {:error, %Ecto.Changeset{} = changeset} =
               Webhooks.create_endpoint(account.id, valid_attrs(%{"url" => "http://example.com/hook"}))

      assert "must be a valid HTTPS URL" in errors_on(changeset).url
    end

    test "rejects a blank name" do
      account = AccountsFixtures.user_fixture().account

      assert {:error, %Ecto.Changeset{} = changeset} =
               Webhooks.create_endpoint(account.id, valid_attrs(%{"name" => ""}))

      assert errors_on(changeset).name != []
    end

    test "rejects an empty event_types list" do
      account = AccountsFixtures.user_fixture().account

      assert {:error, %Ecto.Changeset{} = changeset} =
               Webhooks.create_endpoint(account.id, valid_attrs(%{"event_types" => []}))

      assert errors_on(changeset).event_types != []
    end

    test "rejects unsupported event types" do
      account = AccountsFixtures.user_fixture().account

      assert {:error, %Ecto.Changeset{} = changeset} =
               Webhooks.create_endpoint(account.id, valid_attrs(%{"event_types" => ["nope.exploded"]}))

      assert "contains an unsupported event type" in errors_on(changeset).event_types
    end
  end

  describe "list_endpoints/1 + get_account_endpoint/2" do
    test "scopes to the requesting account" do
      a = AccountsFixtures.user_fixture().account
      b = AccountsFixtures.user_fixture().account
      {:ok, a_endpoint, _} = Webhooks.create_endpoint(a.id, valid_attrs(%{"name" => "A", "url" => "https://a.example/h"}))

      {:ok, _b_endpoint, _} =
        Webhooks.create_endpoint(b.id, valid_attrs(%{"name" => "B", "url" => "https://b.example/h"}))

      assert [endpoint] = Webhooks.list_endpoints(a.id)
      assert endpoint.id == a_endpoint.id

      assert {:ok, _} = Webhooks.get_account_endpoint(a_endpoint.id, a.id)
      assert {:error, :not_found} = Webhooks.get_account_endpoint(a_endpoint.id, b.id)
    end
  end

  describe "list_endpoints_subscribed_to/2" do
    test "returns only endpoints that subscribe to the requested event type and account" do
      a = AccountsFixtures.user_fixture().account
      b = AccountsFixtures.user_fixture().account
      {:ok, a_endpoint, _} = Webhooks.create_endpoint(a.id, valid_attrs(%{"event_types" => ["test_case.updated"]}))
      {:ok, _b_endpoint, _} = Webhooks.create_endpoint(b.id, valid_attrs(%{"event_types" => ["test_case.updated"]}))

      assert [endpoint] = Webhooks.list_endpoints_subscribed_to(a.id, "test_case.updated")
      assert endpoint.id == a_endpoint.id

      assert [] = Webhooks.list_endpoints_subscribed_to(a.id, "missing.event")
    end
  end

  describe "rotate_signing_secret/1" do
    test "replaces the secret in place and returns the new plaintext" do
      account = AccountsFixtures.user_fixture().account
      {:ok, endpoint, original} = Webhooks.create_endpoint(account.id, valid_attrs())

      assert {:ok, rotated, new_plaintext} = Webhooks.rotate_signing_secret(endpoint)
      assert rotated.id == endpoint.id
      assert new_plaintext != original
      # Scrubbed from the returned struct; the worker path holds the
      # decrypted value.
      assert rotated.signing_secret == nil
      assert {:ok, full} = Webhooks.get_endpoint(endpoint.id)
      assert full.signing_secret == new_plaintext
    end
  end

  describe "delete_endpoint/1" do
    test "removes the endpoint" do
      account = AccountsFixtures.user_fixture().account
      {:ok, endpoint, _} = Webhooks.create_endpoint(account.id, valid_attrs())

      assert {:ok, _} = Webhooks.delete_endpoint(endpoint)
      assert {:error, :not_found} = Webhooks.get_endpoint(endpoint.id)
    end
  end
end
