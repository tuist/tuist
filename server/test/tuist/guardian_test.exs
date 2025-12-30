defmodule Tuist.GuardianTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Guardian
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "subject_for_token/2" do
    test "returns subject for account with claims" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      assert {:ok, to_string(account.id)} == Guardian.subject_for_token(account, %{})
    end
  end

  describe "resource_from_claims/1" do
    test "returns AuthenticatedAccount when type is account" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      claims = %{
        "sub" => to_string(account.id),
        "type" => "account",
        "scopes" => ["qa_run_update", "qa_step_create"]
      }

      assert {:ok, %AuthenticatedAccount{account: %Account{id: account_id}, scopes: scopes}} =
               Guardian.resource_from_claims(claims)

      assert account_id == account.id
      assert scopes == ["qa_run_update", "qa_step_create"]
    end

    test "returns error when account not found" do
      non_existent_id = 99_999_999

      claims = %{
        "sub" => to_string(non_existent_id),
        "type" => "account",
        "scopes" => ["qa_run_update"]
      }

      assert {:error, :resource_not_found} = Guardian.resource_from_claims(claims)
    end

    test "returns user when no type specified" do
      user = AccountsFixtures.user_fixture()

      claims = %{
        "sub" => to_string(user.id)
      }

      assert {:ok, returned_user} = Guardian.resource_from_claims(claims)
      assert returned_user.id == user.id
    end
  end
end
