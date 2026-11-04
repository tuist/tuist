defmodule Tuist.GuardianTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Guardian
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "token storage hashing" do
    test "does not hash stateless cache tokens" do
      user = AccountsFixtures.user_fixture()
      reject(&Bcrypt.hash_pwd_salt/1)

      assert {:ok, token, claims} = Guardian.encode_and_sign(user, %{}, token_type: "cache")
      assert {:ok, ^claims} = Guardian.decode_and_verify(token)
      assert {:error, :invalid_token_type} = Guardian.resource_from_claims(claims)
    end

    test "hashes stored refresh tokens and still supports revocation" do
      user = AccountsFixtures.user_fixture()
      expect(Bcrypt, :hash_pwd_salt, 2, fn _ -> "stored-hash" end)

      assert {:ok, token, claims} = Guardian.encode_and_sign(user, %{}, token_type: "refresh")
      assert {:ok, ^claims} = Guardian.decode_and_verify(token)

      assert %{rows: [["stored-hash"]]} =
               Repo.query!("SELECT jwt FROM guardian_tokens WHERE jti = $1", [claims["jti"]])

      assert {:ok, _, {new_token, new_claims}} = Guardian.refresh(token)
      assert {:error, _} = Guardian.decode_and_verify(token)
      assert {:ok, ^new_claims} = Guardian.decode_and_verify(new_token)

      assert %{rows: [["stored-hash"]]} =
               Repo.query!("SELECT jwt FROM guardian_tokens WHERE jti = $1", [new_claims["jti"]])

      assert {:ok, _} = Guardian.revoke(new_token)
      assert {:error, _} = Guardian.decode_and_verify(new_token)
    end
  end

  describe "subject_for_token/2" do
    test "returns subject for account with claims" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      assert {:ok, to_string(account.id)} == Guardian.subject_for_token(account, %{})
    end

    test "returns subject for authenticated account with claims" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      assert {:ok, to_string(account.id)} ==
               Guardian.subject_for_token(%AuthenticatedAccount{account: account, scopes: []}, %{})
    end
  end

  describe "resource_from_claims/1" do
    test "returns AuthenticatedAccount when type is account" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      claims = %{
        "sub" => to_string(account.id),
        "type" => "account",
        "scopes" => ["preview_create", "cache_read"]
      }

      assert {:ok, %AuthenticatedAccount{account: %Account{id: account_id}, scopes: scopes}} =
               Guardian.resource_from_claims(claims)

      assert account_id == account.id
      assert scopes == ["preview_create", "cache_read"]
    end

    test "includes issued_by user when user_id claim is present" do
      user = AccountsFixtures.user_fixture()
      org = AccountsFixtures.organization_fixture(creator: user)

      claims = %{
        "sub" => to_string(org.account.id),
        "type" => "account",
        "scopes" => ["mcp"],
        "all_projects" => true,
        "user_id" => user.id
      }

      assert {:ok, %AuthenticatedAccount{issued_by: issued_by}} = Guardian.resource_from_claims(claims)
      assert issued_by.id == user.id
    end

    test "issued_by is nil when user_id claim is absent" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      claims = %{
        "sub" => to_string(account.id),
        "type" => "account",
        "scopes" => ["mcp"]
      }

      assert {:ok, %AuthenticatedAccount{issued_by: nil}} = Guardian.resource_from_claims(claims)
    end

    test "returns error when account not found" do
      non_existent_id = 99_999_999

      claims = %{
        "sub" => to_string(non_existent_id),
        "type" => "account",
        "scopes" => ["preview_create"]
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
